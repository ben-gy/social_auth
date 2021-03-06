require 'google_plus'
require 'typhoeus'

module SocialAuth
  class GooglePlusService < Service

    def name
      "Google Plus"
    end

    def self.init_with(auth_token={})
      access_token = fetch_access_token(auth_token)
      request = create_connection(access_token).get('me')

      return create_with_request(
        request.id,
        User.create_with_google_plus_request(request),
        "Authenticated",
        {refresh_token: access_token[:refresh_token]}
      )
    rescue GooglePlus::RequestError => e
      raise InvalidToken.new(e.message)
    end

    def self.connect_with(user, auth_token={}, method="Connected")
      access_token = fetch_access_token(auth_token)
      request = create_connection(access_token).get('me')

      return create_with_request(
        request.id,
        user,
        method,
        {refresh_token: access_token[:refresh_token]}
      )
    rescue GooglePlus::RequestError => e
      raise InvalidToken.new(e.message)
    end

    def self.fetch_access_token(auth_token={})
      params = {
        client_id: SocialAuth.google_client_id,
        client_secret: SocialAuth.google_client_secret,
        redirect_uri: SocialAuth.google_redirect_uri
      }
      if auth_token[:auth_token].present?
        params[:code] = auth_token[:auth_token]
        params[:grant_type] = "authorization_code"
        request = Typhoeus::Request.new(
          "https://www.googleapis.com/oauth2/v3/token",
          method: :post,
          params: params
        )
      else
        params[:refresh_token] = auth_token[:refresh_token]
        params[:grant_type] = "refresh_token"
        request = Typhoeus::Request.new(
          "https://www.googleapis.com/oauth2/v3/token",
          method: :post,
          params: params
        )
      end

      request.on_complete do |response|
        body =  JSON.parse(response.body).with_indifferent_access
        if response.success?
          return body
        else
          raise InvalidToken.new(body[:error_description])
        end
      end

      request.run
    end

    def self.create_connection(auth_token={})
      GooglePlus.api_key = SocialAuth.google_api_key
      GooglePlus.access_token = auth_token[:access_token]
      GooglePlus::Person
    end

    def google_items
      self.class.create_connection(self.class.fetch_access_token(access_token)).list.items
    end

    def friend_ids
      if redis_instance.exists(redis_key(:friends))
        friend_ids = redis_instance.smembers(redis_key(:friends))
      else
        items = google_items
        friend_ids = items.map(&:id) if items.present?
        if friend_ids.present?
          redis_instance.del(redis_key(:friends))
          redis_instance.sadd(redis_key(:friends), friend_ids)
          redis_instance.expire(redis_key(:friends), REDIS_CACHE)
        else
          return []
        end
      end
      friend_ids

    rescue InvalidToken => e
      disconnect
      return []
    end
  end
end