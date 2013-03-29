require File.dirname(__FILE__) + '/spec_helper'

describe 'Badging Models' do
  include Rack::Test::Methods
  
  def app
    Canvabadges
  end
  
  describe "index" do
    it "should return" do
      get "/"
      last_response.should be_ok
      last_response.body.should match(/Canvabadges are cool/)
    end
  end  
  
  describe "LTI XML config" do
    it "should return valid LTI configuration" do
      get "/canvabadges.xml"
      last_response.should be_ok
      xml = Nokogiri(last_response.body)
      xml.css('blti|launch_url').text.should == "https://example.org/placement_launch"
    end
  end  
  
  describe "public badge page" do
    it "should fail gracefully if invalid nonce provided" do
      get "/badges/criteria/123"
      last_response.should_not be_ok
      assert_error_page("Badge not found")
    end
    
    it "should return badge completion requirements for valid badge" do
      badge_config
      get "/badges/criteria/#{@badge_config.nonce}"
      last_response.should be_ok
      last_response.body.should match(/#{@badge_config.settings['name']}/)
    end
    
    it "should return badge completion information if the user has earned the badge" do
      award_badge(badge_config, user)
      get "/badges/criteria/#{@badge_config.nonce}?user=#{@badge.nonce}"
      last_response.should be_ok
      last_response.body.should match(/completed the requirements/)
      last_response.body.should match(/#{@badge.user_name}/)
    end
  end  
  
  describe "public badges for user" do
    it "should fail gracefully for invalid domain or user id" do
      user
      get "/badges/all/00/#{@user.user_id}"
      last_response.should be_ok
      assert_error_page("No Badges Earned or Shared")
      
      get "/badges/all/#{@domain.id}/00"
      last_response.should be_ok
      assert_error_page("No Badges Earned or Shared")
    end
    
    it "should return badge completion/publicity information for the current user" do
      award_badge(badge_config, user)
      get "/badges/all/#{@domain.id}/#{@user.user_id}", {}, 'rack.session' => {"domain_id" => @domain.id.to_s, 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should match(/#{@badge.name}/)
      last_response.body.should match(/Share this Page/)
      
      @badge.public = true
      @badge.save
      
      get "/badges/all/#{@domain.id}/#{@user.user_id}", {}, 'rack.session' => {"domain_id" => @domain.id.to_s, 'user_id' => @user.user_id}
      last_response.should be_ok
      last_response.body.should match(/#{@badge.name}/)
      last_response.body.should match(/Share this Page/)
    end
    
    it "should return badge summary for someone other than the current user" do
      award_badge(badge_config, user)
      get "/badges/all/#{@domain.id}/#{@user.user_id}"
      last_response.should be_ok
      assert_error_page("No Badges Earned or Shared")
      
      @badge.public = true
      @badge.save
      
      get "/badges/all/#{@domain.id}/#{@user.user_id}"
      last_response.body.should match(/#{@badge.name}/)
      last_response.body.should_not match(/Share this Page/)
    end
  end  
  
  describe "badge launch page" do
    it "should fail gracefully on invalid course, user or domain parameters" do
      badge_config
      user
      get "/badges/check/00/#{@badge_config.placement_id}/#{@user.user_id}"
      last_response.should_not be_ok
      assert_error_page("Configuration not found")

      get "/badges/check/#{@domain.id}/00/#{@user.user_id}"
      last_response.should_not be_ok
      assert_error_page("Configuration not found")
      
      get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/00"
      last_response.should_not be_ok
      assert_error_page("Session information lost")
    end
    
    it "should allow instructors/admins to configure unconfigured badges" do
      badge_config
      user
      BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}/modules", @user).and_return([])
      get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'edit'}
      last_response.should be_ok
      last_response.body.should match(/Badge reference code/)
    end
    
    it "should not allow students to see unconfigured badges" do
      badge_config
      user
      get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view'}
      last_response.should be_ok
      last_response.body.should match(/Your teacher hasn't set up this badge yet/)
    end
    
    it "should check completion information if the current user is a student" do
      configured_badge
      user

      BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 40}]})
      get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view'}
      last_response.should be_ok
      last_response.body.should match(/Cool Badge/)
    end
    
    describe "meeting completion criteria as a student" do
      it "should award the badge if final grade is the only criteria and is met" do
        configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 60}]})
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        @badge = Badge.last
        @badge.should_not be_nil
        @badge.user_id.should == @user.user_id
        @badge.state.should == 'awarded'
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
      
      it "should not award the badge if final grade criteria is not met" do
        configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 40}]})
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        Badge.last.should be_nil
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
      
      it "should award the badge if final grade and module completions are met" do
        module_configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 60}]})
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}/modules", @user).and_return([{'id' => 1, 'completed_at' => 'now'}, {'id' => 2, 'completed_at' => 'now'}])
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        @badge = Badge.last
        @badge.should_not be_nil
        @badge.user_id.should == @user.user_id
        @badge.state.should == 'awarded'
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
      
      it "should not award the badge if final grade is met but not module completions" do
        module_configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 60}]})
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}/modules", @user).and_return([])
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        Badge.last.should be_nil
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
      
      it "should award the badge if enough credits are earned" do
        credit_configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 60}]})
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}/modules", @user).and_return([{'id' => 1, 'completed_at' => 'now'}, {'id' => 2}])
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        @badge = Badge.last
        @badge.should_not be_nil
        @badge.user_id.should == @user.user_id
        @badge.state.should == 'awarded'
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
      
      it "should not award the badge if enough credits haven't been earned" do
        module_configured_badge
        user
        Badge.last.should be_nil
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}?include[]=total_scores", @user).and_return({'enrollments' => [{'type' => 'student', 'computed_final_score' => 60}]})
        BadgeHelpers.should_receive(:api_call).with("/api/v1/courses/#{@badge_config.course_id}/modules", @user).and_return([])
        get "/badges/check/#{@domain.id}/#{@badge_config.placement_id}/#{@user.user_id}", {}, 'rack.session' => {'user_id' => @user.user_id, "permission_for_#{@badge_config.course_id}" => 'view', 'email' => 'student@example.com'}
        Badge.last.should be_nil
        last_response.should be_ok
        last_response.body.should match(/Cool Badge/)
      end
    end
  end    
end