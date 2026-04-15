# frozen_string_literal: true

module RedmineSaml
  class Base
    class << self
      attr_reader :saml

      def on_login(&block)
        @block = block
      end

      def on_login_callback
        @block ||= nil # rubocop: disable Naming/MemoizedInstanceVariableName
      end

      def saml=(val)
        @saml = ActiveSupport::HashWithIndifferentAccess.new val
      end

      def configured_saml
        raise_configure_exception unless validated_configuration?
        saml
      end

      def configure(&block)
        raise_configure_exception if block.nil?
        yield self
        validate_configuration!
      end

      def attribute_mapping_sep
        configured_saml[:attribute_mapping_sep].presence || '|'
      end

      def user_attributes_from_saml(omniauth)
        Rails.logger.info "user_attributes_from_saml: #{omniauth.inspect}"

        ActiveSupport::HashWithIndifferentAccess.new.tap do |h|
          required_attribute_mapping.each do |symbol|
            key = configured_saml[:attribute_mapping][symbol]
            # Get an array with nested keys: name|first will return [name, first]
            h[symbol] = key.split(attribute_mapping_sep)
                           .map { |x| [:[], x.to_sym] } # Create pair elements being :[] symbol and the key
                           .inject(omniauth.deep_symbolize_keys) do |hash, params|
                             hash&.send(*params) # For each key, apply method :[] with key as parameter
                           end
          end

          apply_name_fallbacks! h, omniauth
        end
      end

      def additionals_help_items
        [{ title: 'OmniAuth SAML',
           url: 'https://github.com/omniauth/omniauth-saml#omniauth-saml',
           admin: true }]
      end

      def fallback_name_attributes(omniauth)
        display_name = extract_display_name omniauth
        return {} if display_name.blank?

        firstname, lastname = split_display_name display_name

        {
          firstname: truncate_user_attribute(:firstname, firstname.presence || '-'),
          lastname: truncate_user_attribute(:lastname, lastname.presence || '-')
        }
      end

      private

      def apply_name_fallbacks!(attributes, omniauth)
        return if attributes[:firstname].present? && attributes[:lastname].present?

        fallback_attributes = fallback_name_attributes omniauth
        attributes[:firstname] = fallback_attributes[:firstname] if attributes[:firstname].blank?
        attributes[:lastname] = fallback_attributes[:lastname] if attributes[:lastname].blank?
      end

      def extract_display_name(omniauth)
        data = omniauth.deep_symbolize_keys

        data.dig(:info, :name).presence ||
          data.dig(:extra, :raw_info, :name).presence ||
          data.dig(:extra, :raw_info, :displayname).presence
      end

      def split_display_name(display_name)
        parts = display_name.to_s.strip.split(/\s+/)
        return [display_name, '-'] if parts.size <= 1

        [parts[0..-2].join(' '), parts[-1]]
      end

      def truncate_user_attribute(attribute, value)
        limit = User.columns_hash[attribute.to_s]&.limit || 255
        value.to_s.slice(0, limit)
      end

      def validated_configuration?
        @validated_configuration ||= false
      end

      def required_attribute_mapping
        %i[login firstname lastname mail]
      end

      def validate_configuration!
        %i[assertion_consumer_service_url
           sp_entity_id
           idp_slo_service_url
           idp_sso_service_url
           name_identifier_format
           name_identifier_value
           attribute_mapping].each do |k|
          raise "RedmineSaml.configure requires saml.#{k} to be set" unless saml[k]
        end

        unless saml[:idp_cert_fingerprint] || saml[:idp_cert] || saml[:idp_cert_multi]
          raise 'RedmineSaml.configure requires either :idp_cert or :idp_cert_multi or :idp_cert_fingerprint to be set'
        end

        required_attribute_mapping.each do |k|
          raise "RedmineSaml.configure requires saml.attribute_mapping[#{k}] to be set" unless saml[:attribute_mapping][k]
        end

        raise 'RedmineSaml on_login must be a Proc only' if on_login_callback && !on_login_callback.is_a?(Proc)

        @validated_configuration = true

        configure_omniauth_saml_middleware
      end

      def raise_configure_exception
        raise 'RedmineSaml must be configured from an initializer. See README of redmine_saml for instructions'
      end

      def configure_omniauth_saml_middleware
        saml_options = configured_saml
        Rails.application.config.middleware.use ::OmniAuth::Builder do
          provider :saml, saml_options
        end
      end
    end
  end
end
