# frozen_string_literal: true

require "spec_helper"

RSpec.describe Widget, type: :model do
  let(:widget) { Widget.create! name: "Bob", an_integer: 1 }

  describe "`be_versioned` matcher" do
    it { is_expected.to be_versioned }
  end

  describe "`have_a_version_with` matcher", versioning: true do
    before do
      widget.update_attributes!(name: "Leonard", an_integer: 1)
      widget.update_attributes!(name: "Tom")
      widget.update_attributes!(name: "Bob")
    end

    it "is possible to do assertions on version attributes" do
      expect(widget).to have_a_version_with name: "Leonard", an_integer: 1
      expect(widget).to have_a_version_with an_integer: 1
      expect(widget).to have_a_version_with name: "Tom"
    end
  end

  describe "versioning option" do
    context "enabled", versioning: true do
      it "enables versioning" do
        expect(widget.versions.size).to eq(1)
      end
    end

    context "disabled (default)" do
      it "does not enable versioning" do
        expect(widget.versions.size).to eq(0)
      end
    end
  end

  describe "Callbacks", versioning: true do
    describe "before_save" do
      it "resets value for timestamp attrs for update so that value gets updated properly" do
        widget.update_attributes!(name: "Foobar")
        w = widget.versions.last.reify
        # Travel 1 second because MySQL lacks sub-second resolution
        Timecop.travel(1) do
          expect { w.save! }.to change(w, :updated_at)
        end
      end
    end

    describe "after_create" do
      let(:widget) { Widget.create!(name: "Foobar", created_at: Time.now - 1.week) }

      it "corresponding version uses the widget's `updated_at`" do
        expect(widget.versions.last.created_at.to_i).to eq(widget.updated_at.to_i)
      end
    end

    describe "after_update" do
      before do
        widget.update_attributes!(name: "Foobar", updated_at: Time.now + 1.week)
      end

      it "clears the `versions_association_name` virtual attribute" do
        w = widget.versions.last.reify
        expect(w.paper_trail).not_to be_live
        w.save!
        expect(w.paper_trail).to be_live
      end

      it "corresponding version uses the widget updated_at" do
        expect(widget.versions.last.created_at.to_i).to eq(widget.updated_at.to_i)
      end
    end

    describe "after_destroy" do
      it "creates a version for that event" do
        expect { widget.destroy }.to change(widget.versions, :count).by(1)
      end

      it "assigns the version into the `versions_association_name`" do
        expect(widget.version).to be_nil
        widget.destroy
        expect(widget.version).not_to be_nil
        expect(widget.version).to eq(widget.versions.last)
      end
    end

    describe "after_rollback" do
      let(:rolled_back_name) { "Big Moo" }

      before do
        begin
          widget.transaction do
            widget.update_attributes!(name: rolled_back_name)
            widget.update_attributes!(name: Widget::EXCLUDED_NAME)
          end
        rescue ActiveRecord::RecordInvalid
          widget.reload
          widget.name = nil
          widget.save
        end
      end

      it "does not create an event for changes that did not happen" do
        widget.versions.map(&:changeset).each do |changeset|
          expect(changeset.fetch("name", [])).not_to include(rolled_back_name)
        end
      end

      it "has not yet loaded the assocation" do
        expect(widget.versions).not_to be_loaded
      end
    end
  end

  describe "Association", versioning: true do
    describe "sort order" do
      it "sorts by the timestamp order from the `VersionConcern`" do
        expect(widget.versions.to_sql).to eq(
          widget.versions.reorder(PaperTrail::Version.timestamp_sort_order).to_sql
        )
      end
    end
  end

  if defined?(ActiveRecord::IdentityMap) && ActiveRecord::IdentityMap.respond_to?(:without)
    describe "IdentityMap", versioning: true do
      it "does not clobber the IdentityMap when reifying" do
        widget.update_attributes name: "Henry", created_at: Time.now - 1.day
        widget.update_attributes name: "Harry"
        allow(ActiveRecord::IdentityMap).to receive(:without)
        widget.versions.last.reify
        expect(ActiveRecord::IdentityMap).to have_receive(:without).once
      end
    end
  end

  describe "#create", versioning: true do
    it "creates a version record" do
      wordget = Widget.create
      assert_equal 1, wordget.versions.length
    end
  end

  describe "#destroy", versioning: true do
    it "creates a version record" do
      widget = Widget.create
      assert_equal 1, widget.versions.length
      widget.destroy
      versions_for_widget = PaperTrail::Version.with_item_keys("Widget", widget.id)
      assert_equal 2, versions_for_widget.length
    end

    it "can have multiple destruction records" do
      versions = lambda { |widget|
        # Workaround for AR 3. When we drop AR 3 support, we can simply use
        # the `widget.versions` association, instead of `with_item_keys`.
        PaperTrail::Version.with_item_keys("Widget", widget.id)
      }
      widget = Widget.create
      assert_equal 1, widget.versions.length
      widget.destroy
      assert_equal 2, versions.call(widget).length
      widget = widget.version.reify
      widget.save
      assert_equal 3, versions.call(widget).length
      widget.destroy
      assert_equal 4, versions.call(widget).length
      assert_equal 2, versions.call(widget).where(event: "destroy").length
    end
  end

  describe "#paper_trail.originator", versioning: true do
    describe "return value" do
      let(:orig_name) { FFaker::Name.name }
      let(:new_name) { FFaker::Name.name }

      before do
        PaperTrail.request.whodunnit = orig_name
      end

      it "returns the originator for the model at a given state" do
        expect(widget.paper_trail).to be_live
        expect(widget.paper_trail.originator).to eq(orig_name)
        ::PaperTrail.request(whodunnit: new_name) {
          widget.update_attributes(name: "Elizabeth")
        }
        expect(widget.paper_trail.originator).to eq(new_name)
      end

      it "returns the appropriate originator" do
        widget.update_attributes(name: "Andy")
        PaperTrail.request.whodunnit = new_name
        widget.update_attributes(name: "Elizabeth")
        reified_widget = widget.versions[1].reify
        expect(reified_widget.paper_trail.originator).to eq(orig_name)
        expect(reified_widget).not_to be_new_record
      end

      it "can create a new instance with options[:dup]" do
        widget.update_attributes(name: "Andy")
        PaperTrail.request.whodunnit = new_name
        widget.update_attributes(name: "Elizabeth")
        reified_widget = widget.versions[1].reify(dup: true)
        expect(reified_widget.paper_trail.originator).to eq(orig_name)
        expect(reified_widget).to be_new_record
      end
    end
  end

  describe "#version_at", versioning: true do
    context "Timestamp argument is AFTER object has been destroyed" do
      it "returns nil" do
        widget.update_attribute(:name, "foobar")
        widget.destroy
        expect(widget.paper_trail.version_at(Time.now)).to be_nil
      end
    end
  end

  describe "#whodunnit", versioning: true do
    it "is deprecated, delegates to Request.whodunnit" do
      allow(::ActiveSupport::Deprecation).to receive(:warn)
      allow(::PaperTrail::Request).to receive(:with)
      widget.paper_trail.whodunnit("Alex") {}
      expect(::ActiveSupport::Deprecation).to have_received(:warn).once
      expect(::PaperTrail::Request).to have_received(:with).with(whodunnit: "Alex")
    end
  end

  describe "#touch_with_version", versioning: true do
    it "creates a version" do
      allow(::ActiveSupport::Deprecation).to receive(:warn)
      count = widget.versions.size
      Timecop.travel(1) do
        widget.paper_trail.touch_with_version
      end
      expect(widget.versions.size).to eq(count + 1)
      expect(::ActiveSupport::Deprecation).to have_received(:warn).once
    end

    it "increments the `:updated_at` timestamp" do
      allow(::ActiveSupport::Deprecation).to receive(:warn)
      time_was = widget.updated_at
      # Travel 1 second because MySQL lacks sub-second resolution
      Timecop.travel(1) do
        widget.paper_trail.touch_with_version
      end
      expect(widget.updated_at).to be > time_was
      expect(::ActiveSupport::Deprecation).to have_received(:warn).once
    end
  end

  describe "touch", versioning: true do
    it "creates a version" do
      expect { widget.touch }.to change {
        widget.versions.count
      }.by(+1)
    end

    it "does not create a version using without_versioning" do
      count = widget.versions.count
      widget.paper_trail.without_versioning do
        widget.touch
      end
      expect(count).to eq(count)
    end
  end

  describe ".paper_trail.update_columns", versioning: true do
    it "creates a version record" do
      widget = Widget.create
      expect(widget.versions.count).to eq(1)
      Timecop.freeze Time.now do
        widget.paper_trail.update_columns(name: "Bugle")
        expect(widget.versions.count).to eq(2)
        expect(widget.versions.last.event).to(eq("update"))
        expect(widget.versions.last.changeset[:name]).to eq([nil, "Bugle"])
        expect(widget.versions.last.created_at.to_i).to eq(Time.now.to_i)
      end
    end
  end

  describe "#update", versioning: true do
    it "creates a version record" do
      widget = Widget.create
      assert_equal 1, widget.versions.length
      widget.update_attributes(name: "Bugle")
      assert_equal 2, widget.versions.length
    end
  end
end
