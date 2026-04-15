# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

class UserTest < RedmineSaml::TestCase
  setup do
    prepare_tests
  end

  context 'User#find_or_create_from_omniauth' do
    should 'find created user' do
      login_name = 'mylogin'
      u = User.new firstname: 'name',
                   lastname: 'last',
                   mail: 'mail@example.net',
                   login: login_name,
                   admin: false

      assert_save u
      assert_not_nil User.find_or_create_from_omniauth(saml_login: login_name)
    end

    context 'onthefly_creation? disabled' do
      setup do
        change_saml_settings onthefly_creation: 0
      end

      should 'return nil when user not exists' do
        assert_nil User.find_or_create_from_omniauth(saml_login: 'not_existent')
      end
    end

    context 'onthefly_creation? enabled' do
      setup do
        change_saml_settings onthefly_creation: 1
      end

      should 'return created user' do
        new = User.find_or_create_from_omniauth saml_login: 'new',
                                                first_name: 'first name',
                                                last_name: 'last name',
                                                mail: 'new@example.com',
                                                admin: false
        assert_not_nil new
        assert_not_nil new.created_on
        assert_operator new.created_on, :<=, Time.zone.now
      end

      should 'fallback missing first and last name from display name' do
        auth = {
          saml_login: 'single-name@example.com',
          first_name: nil,
          last_name: nil,
          mail: 'single-name@example.com',
          info: {
            name: 'Pemberton'
          }
        }

        new = User.find_or_create_from_omniauth auth

        assert_not_nil new
        assert_equal 'Pemberton', new.firstname
        assert_equal '-', new.lastname
      end

      should 'truncate fallback names to fit Redmine limits' do
        auth = {
          saml_login: 'admin@example.com',
          first_name: nil,
          last_name: nil,
          mail: 'admin@example.com',
          info: {
            name: 'Admin Sea to Sky Community Services Society'
          }
        }

        new = User.find_or_create_from_omniauth auth

        assert_not_nil new
        assert_equal 'Admin Sea to Sky Community Ser', new.firstname
        assert_equal 'Society', new.lastname
      end
    end

    context 'different attribute mappings' do
      setup do
        change_saml_settings onthefly_creation: 1
      end

      should 'map single level attribute' do
        attributes = { saml_login: 'new',
                       first_name: 'first name',
                       last_name: 'last name',
                       mail: 'new@example.com',
                       admin: false }

        new = User.find_or_create_from_omniauth attributes

        assert_not_nil new
        assert_equal attributes[:saml_login], new.login
        assert_equal attributes[:first_name], new.firstname
        assert_equal attributes[:last_name], new.lastname
        assert_equal attributes[:mail], new.mail
        assert_equal attributes[:admin], new.admin
      end

      should 'map nested levels attributes' do
        RedmineSaml.configured_saml[:attribute_mapping_sep] = '|'
        RedmineSaml.configured_saml[:attribute_mapping] = { login: 'one|two|three|four|levels|username',
                                                            firstname: 'one|two|three|four|levels|first_name',
                                                            lastname: 'one|two|three|four|levels|last_name',
                                                            mail: 'one|two|three|four|levels|personal_email',
                                                            admin: 'one|two|three|four|levels|is_admin' }

        real_att = { 'username' => 'new',
                     'first_name' => 'first name',
                     'last_name' => 'last name',
                     'personal_email' => 'mail@example.com',
                     'is_admin' => false }

        attributes = { 'one' => { 'two' => { 'three' => { 'four' => { 'levels' => real_att } } } } }

        new_user = User.find_or_create_from_omniauth attributes

        assert_not_nil new_user

        assert_equal real_att['username'], new_user.login
        assert_equal real_att['first_name'], new_user.firstname
        assert_equal real_att['last_name'], new_user.lastname
        assert_equal real_att['personal_email'], new_user.mail
        assert_equal real_att['is_admin'], new_user.admin
      end
    end
  end
end
