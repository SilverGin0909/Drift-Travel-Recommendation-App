from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.output_parsers import JsonOutputParser
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field

# Using Flash-Lite for sub-second classification
router_llm = ChatGoogleGenerativeAI(model="gemini-3.1-flash-lite", temperature=0)

class RouteDecision(BaseModel):
    intent: str = Field(description="One of: 'GREETING', 'TRAVEL_QUERY', 'OFF_TOPIC', 'HATE_SPEECH'")
    direct_response: str = Field(description="A response if the intent is GREETING, OFF_TOPIC, or HATE_SPEECH, otherwise empty.")

router_parser = JsonOutputParser(pydantic_object=RouteDecision)

router_prompt = ChatPromptTemplate.from_messages([
    ("system", (
        "You are a triage assistant for Drift, a KL travel AI. "
        "Classify the user input into one of these intents: 'GREETING', 'TRAVEL_QUERY', 'OFF_TOPIC', or 'HATE_SPEECH'.\n\n"
        "RULES:\n"
        "1. If the input contains offensive words, slurs, derogatory remarks, racist or biased phrasing, leading questions containing racial/ethnic bias, cultural insensitivity, or invasive language targeting protected groups, you MUST classify the intent as 'HATE_SPEECH'.\n"
        "   For 'HATE_SPEECH', you MUST provide exactly the following statement in 'direct_response':\n"
        "   \"I cannot fulfill this request. I am programmed to be a helpful and harmless travel assistant, and I will not engage with or generate racist, discriminatory, or hateful content.\"\n"
        "2. If intent is 'GREETING' (and not 'HATE_SPEECH'), you MUST provide a friendly 'direct_response'.\n"
        "3. If intent is 'TRAVEL_QUERY' (and not 'HATE_SPEECH'), set 'direct_response' to an empty string.\n"
        "4. If intent is 'OFF_TOPIC' (and not 'HATE_SPEECH'), set 'direct_response' to a polite refusal.\n\n"
        "Respond strictly in JSON format."
    )),
    ("human", "{input}")
])

# The Router Chain
router_chain = router_prompt | router_llm | router_parser