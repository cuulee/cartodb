require_relative '../../spec_helper_min'
require_relative '../../factories/organizations_contexts'

describe Admin::OrganizationsController do
  include Warden::Test::Helpers
  include_context 'organization with users helper'

  let(:out_of_quota_message) { "Your organization has run out of quota" }
  let(:out_of_seats_message) { "Your organization has run out of seats" }

  before(:all) do
    @org_user_2.org_admin = true
    @org_user_2.save
  end

  describe '#settings' do
    let(:payload) do
      {
        organization: { color: '#ff0000' }
      }
    end

    before(:each) do
      host! "#{@organization.name}.localhost.lan"
      Organization.any_instance.stubs(:update_in_central).returns(true)
    end

    it 'cannot be accessed by non owner users' do
      login_as(@org_user_1, scope: @org_user_1.username)
      get organization_settings_url(user_domain: @org_user_1.username)
      response.status.should eq 404

      login_as(@org_user_2, scope: @org_user_2.username)
      get organization_settings_url(user_domain: @org_user_2.username)
      response.status.should eq 404
    end

    it 'cannot be updated by non owner users' do
      login_as(@org_user_1, scope: @org_user_1.username)
      put organization_settings_update_url(user_domain: @org_user_1.username), payload
      response.status.should eq 404

      login_as(@org_user_2, scope: @org_user_2.username)
      put organization_settings_update_url(user_domain: @org_user_2.username), payload
      response.status.should eq 404
    end

    it 'can be accessed by owner user' do
      login_as(@org_user_owner, scope: @org_user_owner.username)
      get organization_settings_url(user_domain: @org_user_owner.username)
      response.status.should eq 200
    end

    it 'can be updated by owner user' do
      login_as(@org_user_owner, scope: @org_user_owner.username)
      put organization_settings_update_url(user_domain: @org_user_owner.username), payload
      response.status.should eq 302
    end
  end

  describe '#auth' do
    let(:payload) do
      {
        organization: {
          whitelisted_email_domains: '',
          auth_username_password_enabled: true,
          auth_google_enabled: true,
          auth_github_enabled: true,
          strong_passwords_enabled: false
        }
      }
    end

    before(:each) do
      host! "#{@organization.name}.localhost.lan"
      login_as(@org_user_owner, scope: @org_user_owner.username)
      Organization.any_instance.stubs(:update_in_central).returns(true)
    end

    it 'cannot be accessed by non owner users' do
      login_as(@org_user_1, scope: @org_user_1.username)
      get organization_auth_url(user_domain: @org_user_1.username)
      response.status.should eq 404

      login_as(@org_user_2, scope: @org_user_2.username)
      get organization_auth_url(user_domain: @org_user_2.username)
      response.status.should eq 404
    end

    it 'cannot be updated by non owner users' do
      login_as(@org_user_1, scope: @org_user_1.username)
      put organization_auth_update_url(user_domain: @org_user_1.username), payload
      response.status.should eq 404

      login_as(@org_user_2, scope: @org_user_2.username)
      put organization_auth_update_url(user_domain: @org_user_2.username), payload
      response.status.should eq 404
    end

    it 'can be accessed by owner user' do
      login_as(@org_user_owner, scope: @org_user_owner.username)
      get organization_auth_url(user_domain: @org_user_owner.username)
      response.status.should eq 200
    end

    it 'can be updated by owner user' do
      login_as(@org_user_owner, scope: @org_user_owner.username)
      put organization_auth_update_url(user_domain: @org_user_owner.username), payload
      response.status.should eq 302
    end

    describe 'signup enabled' do
      before(:all) do
        @organization.whitelisted_email_domains = ['carto.com']
        @organization.save
      end

      before(:each) do
        @organization.signup_page_enabled.should eq true
      end

      it 'does not display out warning messages if organization signup would work' do
        @organization.unassigned_quota.should > @organization.default_quota_in_bytes

        get organization_auth_url(user_domain: @org_user_owner.username)

        response.status.should eq 200
        response.body.should_not include(out_of_quota_message)
        response.body.should_not include(out_of_seats_message)
      end

      it 'displays out of quota message if there is no remaining quota' do
        old_quota_in_bytes = @organization.quota_in_bytes

        old_remaining_quota = @organization.unassigned_quota
        new_quota = (@organization.quota_in_bytes - old_remaining_quota) + (@organization.default_quota_in_bytes / 2)
        @organization.reload
        @org_user_owner.reload
        @organization.quota_in_bytes = new_quota
        @organization.save

        get organization_auth_url(user_domain: @org_user_owner.username)

        response.status.should eq 200
        response.body.should include(out_of_quota_message)

        @organization.quota_in_bytes = old_quota_in_bytes
        @organization.save
      end

      it 'displays out of seats message if there are no seats left' do
        old_seats = @organization.seats

        new_seats = @organization.seats - @organization.remaining_seats
        @organization.reload
        @org_user_owner.reload
        @organization.seats = new_seats
        @organization.save

        get organization_auth_url(user_domain: @org_user_owner.username)

        response.status.should eq 200
        response.body.should include(out_of_seats_message)

        @organization.seats = old_seats
        @organization.save
      end
    end

    describe 'signup disabled' do
      before(:all) do
        @organization.whitelisted_email_domains = []
        @organization.save
      end

      before(:each) do
        @organization.signup_page_enabled.should eq false
      end

      it 'does not display out warning messages even without quota and seats' do
        old_quota_in_bytes = @organization.quota_in_bytes
        old_seats = @organization.seats

        @organization.reload
        @org_user_owner.reload

        @organization.seats = @organization.assigned_seats
        @organization.quota_in_bytes = @organization.assigned_quota + 1
        @organization.save

        get organization_auth_url(user_domain: @org_user_owner.username)

        response.status.should eq 200
        response.body.should_not include(out_of_quota_message)
        response.body.should_not include(out_of_seats_message)

        @organization.quota_in_bytes = old_quota_in_bytes
        @organization.seats = old_seats
        @organization.save
      end
    end
  end

  shared_examples_for 'notifications' do
    before(:each) do
      host! "#{@organization.name}.localhost.lan"
      login_as(@admin_user, scope: @admin_user.username)
    end

    describe '#notifications' do
      it 'displays last notification' do
        body = 'Free meal today'
        FactoryGirl.create(:notification, organization: @carto_organization, body: body)
        get organization_notifications_admin_url(user_domain: @admin_user.username)
        response.status.should eq 200
        response.body.should include(body)
      end
    end

    describe '#new_notification' do
      it 'creates a new notification' do
        params = {
          body: 'the body',
          recipients: Carto::Notification::RECIPIENT_ALL
        }
        post new_organization_notification_admin_url(user_domain: @admin_user.username), carto_notification: params
        response.status.should eq 302
        flash[:success].should eq 'Notification sent!'
        notification = @carto_organization.reload.notifications.first
        notification.body.should eq params[:body]
        notification.recipients.should eq params[:recipients]
        notification.icon.should eq Carto::Notification::ICON_ALERT
      end
    end

    describe '#destroy_notification' do
      it 'destroys a notification' do
        notification = @carto_organization.notifications.first
        delete destroy_organization_notification_admin_url(user_domain: @admin_user.username, id: notification.id)
        response.status.should eq 302
        flash[:success].should eq 'Notification was successfully deleted!'
        @carto_organization.reload.notifications.should_not include(notification)
      end
    end
  end

  describe 'with organization owner' do
    it_behaves_like 'notifications' do
      before(:all) do
        @admin_user = @org_user_owner
      end
    end
  end

  describe 'with organization admin' do
    it_behaves_like 'notifications' do
      before(:all) do
        @admin_user = @org_user_2
      end
    end
  end
end