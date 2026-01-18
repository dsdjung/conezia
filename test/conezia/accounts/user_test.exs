defmodule Conezia.Accounts.UserTest do
  use Conezia.DataCase, async: true

  alias Conezia.Accounts.User

  describe "changeset/2" do
    test "valid changeset with required fields" do
      changeset = User.changeset(%User{}, %{email: "test@example.com"})
      assert changeset.valid?
    end

    test "invalid changeset without email" do
      changeset = User.changeset(%User{}, %{})
      refute changeset.valid?
      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid changeset with invalid email format" do
      changeset = User.changeset(%User{}, %{email: "notanemail"})
      refute changeset.valid?
      assert %{email: ["must be a valid email"]} = errors_on(changeset)
    end

    test "email is downcased" do
      changeset = User.changeset(%User{}, %{email: "TEST@EXAMPLE.COM"})
      assert get_change(changeset, :email) == "test@example.com"
    end

    test "validates timezone" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", timezone: "Invalid/Zone"})
      refute changeset.valid?
      assert %{timezone: ["must be a valid IANA timezone"]} = errors_on(changeset)
    end

    test "accepts valid timezone" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", timezone: "America/New_York"})
      assert changeset.valid?
    end

    test "validates tier inclusion" do
      changeset = User.changeset(%User{}, %{email: "test@example.com", tier: "invalid"})
      refute changeset.valid?
      assert %{tier: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts valid tier" do
      for tier <- ~w(free personal professional enterprise) do
        changeset = User.changeset(%User{}, %{email: "test@example.com", tier: tier})
        assert changeset.valid?
      end
    end
  end

  describe "registration_changeset/2" do
    test "valid registration with password" do
      changeset = User.registration_changeset(%User{}, %{
        email: "test@example.com",
        password: "Password123"
      })
      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
    end

    test "validates password length" do
      changeset = User.registration_changeset(%User{}, %{
        email: "test@example.com",
        password: "short"
      })
      refute changeset.valid?
      assert %{password: ["should be at least 8 character(s)"]} = errors_on(changeset)
    end

    test "validates password has lowercase" do
      changeset = User.registration_changeset(%User{}, %{
        email: "test@example.com",
        password: "PASSWORD123"
      })
      refute changeset.valid?
      assert %{password: ["must contain a lowercase letter"]} = errors_on(changeset)
    end

    test "validates password has uppercase" do
      changeset = User.registration_changeset(%User{}, %{
        email: "test@example.com",
        password: "password123"
      })
      refute changeset.valid?
      assert %{password: ["must contain an uppercase letter"]} = errors_on(changeset)
    end

    test "validates password has number" do
      changeset = User.registration_changeset(%User{}, %{
        email: "test@example.com",
        password: "PasswordNoNum"
      })
      refute changeset.valid?
      assert %{password: ["must contain a number"]} = errors_on(changeset)
    end
  end

  describe "password_changeset/2" do
    test "hashes password" do
      user = %User{email: "test@example.com"}
      changeset = User.password_changeset(user, %{password: "NewPassword123"})
      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
    end
  end

  describe "valid_password?/2" do
    test "returns true for valid password" do
      user = %User{hashed_password: Argon2.hash_pwd_salt("Password123")}
      assert User.valid_password?(user, "Password123")
    end

    test "returns false for invalid password" do
      user = %User{hashed_password: Argon2.hash_pwd_salt("Password123")}
      refute User.valid_password?(user, "WrongPassword")
    end

    test "returns false for nil user" do
      refute User.valid_password?(nil, "Password123")
    end
  end

  describe "preferences_changeset/2" do
    test "valid preferences update" do
      user = %User{email: "test@example.com"}
      changeset = User.preferences_changeset(user, %{
        settings: %{theme: "dark"},
        notification_preferences: %{"email" => false}
      })
      assert changeset.valid?
    end
  end
end
