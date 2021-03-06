require 'spec_helper'

module SocialAuth
  describe TwitterService do
    before :each do
      @user = User.create(email: "email@address.com")
      #have since been revoked so use vcr records
      SocialAuth.twitter_consumer_key = "MxzWRgtXC2CVc71azEnN9u2Df"
      SocialAuth.twitter_consumer_secret = "QxNG8LukvzeAayj7igWazoUks9DtluNPn6D6Ej60bmu9z8uzM4"
      allow_any_instance_of(TwitterService).to receive(:redis_instance).and_return(Redis.new)
      allow_any_instance_of(TwitterService).to receive(:append_to_associated_services).and_return(true)
    end

    describe "social login methods" do
      it "receives init_with on authenticate" do
        expect(TwitterService).to receive(:init_with)
        SocialAuth.authenticate("twitter", {access_token: "access_token", access_token_secret: "secret_token"})
      end

      it "receives connect_with on connect" do
        expect(TwitterService).to receive(:connect_with)
        SocialAuth.connect(@user, "twitter", {access_token: "access_token", access_token_secret: "secret_token"})
      end
    end

    describe "self.init_with" do
      before :each do
        #create an override method on user which gets called whenever
        #we want a user created you do the rest!
        User.class_eval do
          has_many :services, inverse_of: :user, class_name: SocialAuth::Service
          def self.create_with_twitter_request(request)
            new
          end
        end
      end

      it "creates service if doesn't exist" do
        VCR.use_cassette('twitter_service/valid_request') do
          expect{
            TwitterService.init_with(twitter_access_token)
          }.to change(TwitterService, :count).by(1)
        end
      end

      it "User receives override method" do
        expect(User).to receive(:create_with_twitter_request).once
        VCR.use_cassette('twitter_service/valid_request') do
          TwitterService.init_with(twitter_access_token)
        end
      end
    end

    describe "create_connection" do
      it "returns valid connection" do
        VCR.use_cassette('facebook_service/valid_request') do
          expect{
            TwitterService.create_connection(twitter_access_token)
          }.to_not raise_error
        end
      end
    end

    describe "self.connect_with" do
      it "creates service if doesn't exist" do
        VCR.use_cassette('twitter_service/valid_request') do
          expect{
            TwitterService.connect_with(@user, twitter_access_token)
          }.to change(TwitterService, :count).by(1)
        end
      end
    end

    describe "friend_ids" do
      before :each do
        @service = TwitterService.create(access_token: twitter_access_token, remote_id: "410739240", user: @user, method: "Authenticated")
      end

      it "returns friend_ids" do
        VCR.use_cassette("twitter_service/valid_friends_request") do
          expect{
            expect(@service.friend_ids).to_not be_empty
          }.to_not raise_error
        end
      end

      it "invalid_token returns empty array and hits disconnect callback" do
        service = TwitterService.create(access_token: {access_token: "test", access_token_secret: "fake"}, remote_id: "410739240", user: @user, method: "Authenticated")
        expect_any_instance_of(TwitterService).to receive(:disconnect).once
        VCR.use_cassette("twitter_service/invalid_friends_request") do
          expect{
            expect(service.friend_ids).to be_empty
          }.to_not raise_error
        end
      end

    end

  end
end