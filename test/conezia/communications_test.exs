defmodule Conezia.CommunicationsTest do
  use Conezia.DataCase, async: true

  alias Conezia.Communications
  alias Conezia.Communications.{Conversation, Communication}

  import Conezia.Factory

  describe "conversations" do
    test "get_conversation/1 returns conversation" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      assert %Conversation{} = Communications.get_conversation(conversation.id)
    end

    test "get_conversation_for_user/2 returns user's conversation" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      assert %Conversation{} = Communications.get_conversation_for_user(conversation.id, user.id)
    end

    test "list_conversations/2 returns user's conversations" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:conversation, user: user, entity: entity)
      insert(:conversation, user: user, entity: entity)

      {conversations, _meta} = Communications.list_conversations(user.id)
      assert length(conversations) == 2
    end

    test "list_conversations/2 filters by channel" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      insert(:conversation, user: user, entity: entity, channel: "email")
      insert(:conversation, user: user, entity: entity, channel: "sms")

      {email_convs, _} = Communications.list_conversations(user.id, channel: "email")
      assert length(email_convs) == 1
    end

    test "create_conversation/1 creates conversation" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      attrs = %{
        channel: "email",
        external_id: "conv_123",
        user_id: user.id,
        entity_id: entity.id
      }

      assert {:ok, %Conversation{}} = Communications.create_conversation(attrs)
    end

    test "archive_conversation/1 archives conversation" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity, is_archived: false)

      assert {:ok, archived} = Communications.archive_conversation(conversation)
      assert archived.is_archived
    end
  end

  describe "communications" do
    test "get_communication/1 returns communication" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      communication = insert(:communication, entity: entity, conversation: conversation)

      assert %Communication{} = Communications.get_communication(communication.id)
    end

    test "list_communications_for_conversation/2 returns messages" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      insert(:communication, entity: entity, conversation: conversation)
      insert(:communication, entity: entity, conversation: conversation)

      communications = Communications.list_communications_for_conversation(conversation.id)
      assert length(communications) == 2
    end

    test "create_communication/1 creates communication" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      attrs = %{
        direction: "outbound",
        channel: "email",
        subject: "Hello",
        content: "Message content",
        sent_at: DateTime.utc_now(),
        entity_id: entity.id,
        conversation_id: conversation.id
      }

      assert {:ok, %Communication{}} = Communications.create_communication(attrs)
    end

    test "mark_communication_as_read/1 sets read_at" do
      user = insert(:user)
      entity = insert(:entity, owner: user)
      conversation = insert(:conversation, user: user, entity: entity)
      communication = insert(:communication, entity: entity, conversation: conversation, read_at: nil)

      assert {:ok, read} = Communications.mark_communication_as_read(communication)
      assert read.read_at
    end
  end
end
