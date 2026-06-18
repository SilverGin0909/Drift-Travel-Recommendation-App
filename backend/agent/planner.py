from pydantic import BaseModel, Field
from typing import List
from config.config import llm

class Activity(BaseModel):
    time: str = Field(description="Suggested time of day or duration range, e.g., 09:00 AM, Afternoon")
    title: str = Field(description="Name/Title of the activity")
    description: str = Field(description="Description of the activity and highlights")
    location: str = Field(description="Name of the place, neighborhood, or address")

class DayPlan(BaseModel):
    day_number: int = Field(description="Sequential day number, starting at 1")
    theme: str = Field(description="Theme or focus of the day, e.g., Heritage Walk, Nature Trails")
    activities: List[Activity] = Field(description="List of activities for this day")

class Itinerary(BaseModel):
    destination: str = Field(description="Name of the destination")
    duration_days: int = Field(description="Total number of days in the itinerary")
    days: List[DayPlan] = Field(description="List of day-by-day plans")

async def generate_structured_itinerary(query: str, prefs_context: str, existing_itinerary: str = None) -> dict:
    """
    Generates or updates a structured itinerary matching the Itinerary Pydantic schema 
    using the Gemini model's native structured output capability.
    """
    structured_llm = llm.with_structured_output(Itinerary)
    
    if existing_itinerary:
        prompt = (
            "You are an expert travel planner specializing in Kuala Lumpur, Selangor, and wider Malaysia.\n"
            "You are presented with an EXISTING travel itinerary and a user's modification request or follow-up query.\n"
            "Update, modify, or add/delete activities from the existing itinerary as requested by the user, while keeping the rest of the itinerary intact.\n\n"
            f"Existing Itinerary JSON:\n{existing_itinerary}\n\n"
            f"User Modification Query: {query}\n"
            f"User Preferences: {prefs_context}\n\n"
            "Rules:\n"
            "1. Only modify the specific days or activities the user is asking to change or query about. Keep unchanged parts of the itinerary exactly as they were.\n"
            "2. Ensure the resulting itinerary is realistic and geographically logical.\n"
            "3. Output strictly according to the Itinerary schema."
        )
    else:
        prompt = (
            "You are an expert travel planner specializing in Kuala Lumpur, Selangor, and wider Malaysia.\n"
            "Generate a highly detailed, personalized, day-by-day travel itinerary based on the user's query and travel preferences.\n\n"
            f"User Query: {query}\n"
            f"User Preferences: {prefs_context}\n\n"
            "Rules:\n"
            "1. Create logical, geographic groupings of activities for each day to avoid excessive travel time.\n"
            "2. Keep the timeline realistic, allowing enough time for transit, meals, and resting.\n"
            "3. Incorporate local highlights (e.g. food spots, historical landmarks, shopping, wellness) based on the user's preference context.\n"
            "4. Output strictly according to the Itinerary schema."
        )
    
    response = await structured_llm.ainvoke(prompt)
    
    # Convert Pydantic object to dictionary
    return response.model_dump()
