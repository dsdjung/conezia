defmodule Conezia.AccountsTest do
  use Conezia.DataCase, async: true

  alias Conezia.Accounts
  alias Conezia.Accounts.User

  import Conezia.Factory

  describe "get_user/1" do
    test "returns user when exists" do
      user = insert(:user)
      assert %User{} = Accounts.get_user(user.id)
    end

    test "returns nil when user does not exist" do
      assert is_nil(Accounts.get_user(UUID.uuid4()))
    end
  end

  describe "get_user!/1" do
    test "returns user when exists" do
      user = insert(:user)
      assert %User{} = Accounts.get_user!(user.id)
    end

    test "raises when user does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(UUID.uuid4())
      end
    end
  end

  describe "get_user_by_email/1" do
    test "returns user when email exists" do
      user = insert(:user, email: "test@example.com")
      assert %User{id: id} = Accounts.get_user_by_email("test@example.com")
      assert id == user.id
    end

    test "returns user with case-insensitive email" do
      user = insert(:user, email: "test@example.com")
      assert %User{id: id} = Accounts.get_user_by_email("TEST@EXAMPLE.COM")
      assert id == user.id
    end

    test "returns nil when email does not exist" do
      assert is_nil(Accounts.get_user_by_email("nonexistent@example.com"))
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns user with valid credentials" do
      user = insert(:user, hashed_password: Argon2.hash_pwd_salt("Password123"))
      assert %User{id: id} = Accounts.get_user_by_email_and_password(user.email, "Password123")
      assert id == user.id
    end

    test "returns nil with invalid password" do
      user = insert(:user, hashed_password: Argon2.hash_pwd_salt("Password123"))
      assert is_nil(Accounts.get_user_by_email_and_password(user.email, "WrongPassword"))
    end

    test "returns nil when email does not exist" do
      assert is_nil(Accounts.get_user_by_email_and_password("nonexistent@example.com", "Password123"))
    end
  end

  describe "create_user/1" do
    test "creates user with valid data" do
      attrs = %{
        email: "newuser@example.com",
        password: "Password123",
        name: "New User"
      }

      assert {:ok, %User{} = user} = Accounts.create_user(attrs)
      assert user.email == "newuser@example.com"
      assert user.name == "New User"
      assert user.hashed_password
    end

    test "fails with invalid email" do
      attrs = %{email: "invalid", password: "Password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
    end

    test "fails with duplicate email" do
      insert(:user, email: "existing@example.com")
      attrs = %{email: "existing@example.com", password: "Password123"}
      assert {:error, changeset} = Accounts.create_user(attrs)
      assert %{email: ["has already been taken"]} = errors_on(changeset)
    end
  end

  describe "update_user/2" do
    test "updates user with valid data" do
      user = insert(:user)
      assert {:ok, updated_user} = Accounts.update_user(user, %{name: "Updated Name"})
      assert updated_user.name == "Updated Name"
    end

    test "fails with invalid data" do
      user = insert(:user)
      assert {:error, changeset} = Accounts.update_user(user, %{email: "invalid"})
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
    end
  end

  describe "delete_user/1" do
    test "deletes user" do
      user = insert(:user)
      assert {:ok, %User{}} = Accounts.delete_user(user)
      assert is_nil(Accounts.get_user(user.id))
    end
  end

  describe "authenticate_by_email_password/2" do
    test "returns {:ok, user} with valid credentials" do
      user = insert(:user, hashed_password: Argon2.hash_pwd_salt("Password123"))
      assert {:ok, %User{id: id}} = Accounts.authenticate_by_email_password(user.email, "Password123")
      assert id == user.id
    end

    test "returns {:error, :invalid_credentials} with invalid password" do
      user = insert(:user, hashed_password: Argon2.hash_pwd_salt("Password123"))
      assert {:error, :invalid_credentials} = Accounts.authenticate_by_email_password(user.email, "WrongPassword")
    end
  end

  describe "session tokens" do
    test "generate_user_session_token/1 creates token" do
      user = insert(:user)
      token = Accounts.generate_user_session_token(user)
      assert is_binary(token)
    end

    test "get_user_by_session_token/1 returns user" do
      user = insert(:user)
      token = Accounts.generate_user_session_token(user)
      assert %User{id: id} = Accounts.get_user_by_session_token(token)
      assert id == user.id
    end

    test "delete_session_token/1 invalidates token" do
      user = insert(:user)
      token = Accounts.generate_user_session_token(user)
      assert :ok = Accounts.delete_session_token(token)
      assert is_nil(Accounts.get_user_by_session_token(token))
    end
  end

  describe "email verification" do
    test "verify_email_with_token/1 verifies email" do
      user = insert(:user)
      token = Accounts.generate_user_email_token(user, "confirm")

      assert {:ok, verified_user} = Accounts.verify_email_with_token(token)
      assert verified_user.confirmed_at
    end

    test "verify_email_with_token/1 fails with invalid token" do
      assert {:error, :invalid_token} = Accounts.verify_email_with_token("invalid_token")
    end
  end

  describe "onboarding" do
    test "update_onboarding_step/3 updates state" do
      user = insert(:user, onboarding_state: %{})
      {:ok, updated} = Accounts.update_onboarding_step(user, "profile", "complete")
      assert updated.onboarding_state["profile"] == true
    end

    test "complete_onboarding/1 marks onboarding complete" do
      user = insert(:user)
      {:ok, updated} = Accounts.complete_onboarding(user)
      assert updated.onboarding_completed_at
      assert updated.onboarding_state["completed"] == true
    end
  end
end
