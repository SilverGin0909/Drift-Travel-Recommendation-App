from langchain_community.chat_message_histories import SQLChatMessageHistory

def get_session_history(user_id):
    return SQLChatMessageHistory(
        session_id=user_id,
        connection_string="sqlite:///chat_history.db"
    )