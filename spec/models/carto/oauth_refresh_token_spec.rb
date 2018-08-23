# encoding: utf-8

require 'spec_helper_min'

module Carto
  describe OauthRefreshToken do
    describe '#validation' do
      before(:all) do
        @user = FactoryGirl.build(:carto_user)
        @app = FactoryGirl.build(:oauth_app, user: @user)
        @app_user = OauthAppUser.new(user: @user, oauth_app: @app)
      end

      it 'requires offline scope' do
        refresh_token = OauthRefreshToken.new
        expect(refresh_token).not_to(be_valid)
        expect(refresh_token.errors[:scopes]).to(include("must contain `offline`"))
      end

      it 'does not accept invalid scopes' do
        refresh_token = OauthRefreshToken.new(scopes: ['wadus'])
        expect(refresh_token).to_not(be_valid)
        expect(refresh_token.errors[:scopes]).to(include("contains unsuported scopes: wadus"))
      end

      it 'validates with offline scope' do
        refresh_token = OauthRefreshToken.new(oauth_app_user: @app_user, scopes: ['offline'])
        expect(refresh_token).to(be_valid)
      end
    end

    describe '#exchange!' do
      before(:all) do
        @user = FactoryGirl.create(:carto_user)
        @app = FactoryGirl.create(:oauth_app, user: @user)
        @app_user = OauthAppUser.create(user: @user, oauth_app: @app)
      end

      after(:all) do
        @app_user.destroy
        @user.destroy
        @app.destroy
      end

      before(:each) do
        @refresh_token = @app_user.oauth_refresh_tokens.create!(scopes: ['offline'])
      end

      after(:each) do
        @refresh_token.destroy
      end

      it 'fails if the token is expired' do
        @refresh_token.updated_at -= 1.year
        @refresh_token.save!

        expect { @refresh_token.exchange! }.to(raise_error(OauthProvider::Errors::InvalidGrant))
      end

      it 'can exchange multiple times while it has been used in the last 6 months' do
        @refresh_token.exchange!
        Delorean.jump(4.months)
        @refresh_token.exchange!
        Delorean.jump(4.months)
        @refresh_token.exchange!
        Delorean.jump(7.months)
        expect { @refresh_token.exchange! }.to(raise_error(OauthProvider::Errors::InvalidGrant))
      end

      it 'creates a new access token and regenerated the code and updated_at' do
        prev_token = @refresh_token.token
        prev_updated_at = @refresh_token.updated_at

        access_token, refresh_token = @refresh_token.exchange!

        expect(access_token.api_key).to(be)
        expect(access_token.api_key.type).to(eq('oauth'))
        expect(access_token.scopes).to(eq(refresh_token.scopes))

        expect(refresh_token).to(eq(@refresh_token))
        expect(refresh_token.token).to_not(eq(prev_token))
        expect(refresh_token.updated_at).to_not(eq(prev_updated_at))
      end

      it 'creates a new access token with reduced scopes if asked to' do
        access_token, refresh_token = @refresh_token.exchange!(requested_scopes: [])

        expect(access_token.scopes).to(eq([]))
        expect(refresh_token.scopes).to(eq(['offline']))
      end

      it 'throws an error if requesting more scopes than available' do
        expect { @refresh_token.exchange!(requested_scopes: ['not_there']) }.to(
          raise_error(OauthProvider::Errors::InvalidScope)
        )
      end
    end

    describe '#create!' do
      before(:all) do
        @user = FactoryGirl.create(:carto_user)
        @app = FactoryGirl.create(:oauth_app, user: @user)
        @app_user = OauthAppUser.create(user: @user, oauth_app: @app)
      end

      after(:all) do
        @refresh_token.destroy
      end

      it 'keeps one and only one refresh token per OauthAppUser' do
        @app_user.oauth_refresh_tokens.create!(scopes: ['offline'])
        expect(OauthRefreshToken.where(oauth_app_user: @app_user).count).to(eq(1))

        @refresh_token = @app_user.oauth_refresh_tokens.create!(scopes: ['offline'])
        expect(OauthRefreshToken.where(oauth_app_user: @app_user).count).to(eq(1))
      end
    end
  end
end
