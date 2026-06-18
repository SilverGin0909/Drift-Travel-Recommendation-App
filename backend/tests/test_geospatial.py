import sys
import os

# Adjust path to include the backend folder
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from utilities.geospatial import get_closest_neighborhood

def test_closest_neighborhoods():
    # Sepang Town coordinates
    assert get_closest_neighborhood(2.6908, 101.7410) == "Sepang"
    
    # KLIA coordinates
    assert get_closest_neighborhood(2.7456, 101.7072) == "KLIA (Kuala Lumpur International Airport)"
    
    # Cyberjaya coordinates
    assert get_closest_neighborhood(2.9213, 101.6559) == "Cyberjaya"
    
    # Bukit Bintang coordinates
    assert get_closest_neighborhood(3.1478, 101.7100) == "Bukit Bintang"
    
    # Puchong coordinates
    assert get_closest_neighborhood(3.0333, 101.6167) == "Puchong"
    
    # Sri Petaling coordinates
    assert get_closest_neighborhood(3.0697, 101.6965) == "Sri Petaling"
    
    # Chow Kit coordinates
    assert get_closest_neighborhood(3.1636, 101.6980) == "Chow Kit"
    
    # Damansara coordinates
    assert get_closest_neighborhood(3.1373, 101.6233) == "Damansara"
    
    # Hartamas coordinates
    assert get_closest_neighborhood(3.1610, 101.6565) == "Hartamas"
    
    # Kuchai coordinates
    assert get_closest_neighborhood(3.0898, 101.6901) == "Kuchai"
    
    # Pudu coordinates
    assert get_closest_neighborhood(3.1340, 101.7130) == "Pudu"
    
    # None coordinates
    assert get_closest_neighborhood(None, None) == "Kuala Lumpur"
    
    # Far away coordinates (should default to Kuala Lumpur)
    assert get_closest_neighborhood(1.29027, 103.851959) == "Kuala Lumpur" # Singapore
    
    print("All geospatial tests passed successfully!")

if __name__ == "__main__":
    test_closest_neighborhoods()
