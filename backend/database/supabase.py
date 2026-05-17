from config.config import supabase

def get_user_prefs(user_id: str) -> dict:
    """
    Single source of truth for user preferences. 
    Fetches or creates a record and returns consistent keys.
    """
    try:
        res = supabase.rpc("get_my_preferences", {"user_uuid": user_id}).execute()
        return res.data
    except Exception as e:
        print(f"RPC error for user {user_id}: {e}")
        return {
            "budget": "Moderate",
            "style": "General", 
            "interest": "Sightseeing"
        }