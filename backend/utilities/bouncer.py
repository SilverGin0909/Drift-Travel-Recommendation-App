import logging
from pydantic import BaseModel, Field
from langchain_core.prompts import ChatPromptTemplate
from config.config import llm

logger = logging.getLogger(__name__)

class IntentClassification(BaseModel):
    is_travel_related: bool = Field(
        description="True if the user is asking about travel, food, locations, or attractions in Malaysia. General friendly greetings (hi, hello) are also True. False for coding, math, general trivia, or off-topic requests."

    )

bouncer_prompt = ChatPromptTemplate.from_template("""
You are a strict intent classifier. You do not answer questions. 
You only classify if the user's input is related to a Malaysian travel chatbot.
General friendly greetings (hi, hello) are also considered valid.

User Input: {input}
""")

bouncer_chain = bouncer_prompt | llm.with_structured_output(IntentClassification)