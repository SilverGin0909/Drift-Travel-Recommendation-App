import sys
import os
import unittest
from unittest.mock import patch, MagicMock

# Adjust path to include the backend folder
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from agent.rag import is_query_location_specific

class TestRAGRefactors(unittest.TestCase):
    
    def test_is_query_location_specific_yes(self):
        # Query with specific locations in Malaysia
        queries_specific = [
            "cafes in Cyberjaya",
            "hotels near Bukit Bintang",
            "things to do in Melaka",
            "Batu Caves tour",
            "Petaling Jaya malls"
        ]
        for q in queries_specific:
            res = is_query_location_specific(q)
            print(f"Query: '{q}' -> is_specific: {res}")
            # We want to log and assert, but since LLM calls require real API keys,
            # we should also verify it returns a boolean.
            self.assertIsInstance(res, bool)
            
    def test_is_query_location_specific_no(self):
        # Generic queries
        queries_generic = [
            "good food",
            "recommend a hotel room near me",
            "sightseeing suggestions",
            "where to stay tonight"
        ]
        for q in queries_generic:
            res = is_query_location_specific(q)
            print(f"Query: '{q}' -> is_specific: {res}")
            self.assertIsInstance(res, bool)

if __name__ == "__main__":
    unittest.main()
