module PaperTrail
  module Rails
    # Extensions to rails controllers. Provides convenient ways to pass certain
    # information to the model layer, with `controller_info` and `whodunnit`.
    # Also includes a convenient on/off switch, `enabled_for_controller`.
    module Controller
      def self.included(controller)
        controller.before_action(
          :set_paper_trail_enabled_for_controller,
          :set_paper_trail_controller_info
        )
        controller.after_action :warn_about_not_setting_whodunnit
      end

      protected

      # Returns the user who is responsible for any changes that occur.
      # By default this calls `current_user` and returns the result.
      #
      # Override this method in your controller to call a different
      # method, e.g. `current_person`, or anything you like.
      def user_for_paper_trail
        return unless defined?(current_user)
        ActiveSupport::VERSION::MAJOR >= 4 ? current_user.try!(:id) : current_user.try(:id)
      rescue NoMethodError
        current_user
      end

      # Returns any information about the controller or request that you
      # want PaperTrail to store alongside any changes that occur.  By
      # default this returns an empty hash.
      #
      # Override this method in your controller to return a hash of any
      # information you need.  The hash's keys must correspond to columns
      # in your `versions` table, so don't forget to add any new columns
      # you need.
      #
      # For example:
      #
      #     {:ip => request.remote_ip, :user_agent => request.user_agent}
      #
      # The columns `ip` and `user_agent` must exist in your `versions` # table.
      #
      # Use the `:meta` option to
      # `PaperTrail::Model::ClassMethods.has_paper_trail` to store any extra
      # model-level data you need.
      def info_for_paper_trail
        {}
      end

      # Returns `true` (default) or `false` depending on whether PaperTrail
      # should be active for the current request.
      #
      # Override this method in your controller to specify when PaperTrail
      # should be off.
      def paper_trail_enabled_for_controller
        ::PaperTrail.enabled?
      end

      private

      # Tells PaperTrail whether versions should be saved in the current
      # request.
      def set_paper_trail_enabled_for_controller
        ::PaperTrail.enabled_for_controller = paper_trail_enabled_for_controller
      end

      # Tells PaperTrail who is responsible for any changes that occur.
      def set_paper_trail_whodunnit
        @set_paper_trail_whodunnit_called = true
        ::PaperTrail.whodunnit = user_for_paper_trail if ::PaperTrail.enabled_for_controller?
      end

      # Tells PaperTrail any information from the controller you want to store
      # alongside any changes that occur.
      def set_paper_trail_controller_info
        ::PaperTrail.controller_info = info_for_paper_trail if ::PaperTrail.enabled_for_controller?
      end

      def warn_about_not_setting_whodunnit
        return unless ::PaperTrail.enabled_for_controller?

        user_present = user_for_paper_trail.present?
        whodunnit_blank = ::PaperTrail.whodunnit.blank?
        if user_present && whodunnit_blank && !@set_paper_trail_whodunnit_called
          source_file_location = self.class.instance_methods(false).map { |m|
            self.class.instance_method(m).source_location.first
          }.uniq.first
          ::Kernel.warn <<-EOS.strip_heredoc
            #{source_file_location}:
            user_for_paper_trail is present, but whodunnit has not been set.
            PaperTrail no longer adds the set_paper_trail_whodunnit callback for
            you. To continue recording whodunnit, please add this before_action
            callback to your ApplicationController. For more information,
            please see https://git.io/vrTsk
          EOS
        end
      end
    end
  end
end

if defined?(::ActionController)
  ::ActiveSupport.on_load(:action_controller) do
    include ::PaperTrail::Rails::Controller
  end
end
