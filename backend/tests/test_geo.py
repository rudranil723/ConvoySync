import pytest
import math
from app.services.geo import (
    haversine_distance, 
    bearing_difference, 
    calculate_bearing, 
    point_to_segment_distance_meters,
    calculate_cross_track_error_and_road_bearing
)

def test_haversine_distance():
    # Distance from a point to itself should be 0
    assert haversine_distance(0.0, 0.0, 0.0, 0.0) == 0.0
    
    # Distance between Paris (48.8566, 2.3522) and London (51.5074, -0.1278) is approx 344 km
    dist = haversine_distance(48.8566, 2.3522, 51.5074, -0.1278)
    assert 340.0 < dist < 350.0

def test_bearing_difference():
    # Simple differences
    assert bearing_difference(0.0, 90.0) == 90.0
    assert bearing_difference(90.0, 0.0) == 90.0
    
    # Boundary cross-over differences
    assert bearing_difference(350.0, 10.0) == 20.0
    assert bearing_difference(10.0, 350.0) == 20.0
    
    # Max difference
    assert bearing_difference(0.0, 180.0) == 180.0
    assert bearing_difference(0.0, 190.0) == 170.0

def test_calculate_bearing():
    # Bearing from equator (0,0) to north (1,0) should be 0 (North)
    assert round(calculate_bearing(0.0, 0.0, 1.0, 0.0)) == 0
    
    # Bearing from equator (0,0) to east (0,1) should be 90 (East)
    assert round(calculate_bearing(0.0, 0.0, 0.0, 1.0)) == 90

def test_point_to_segment_distance_meters():
    # Segment AB goes East along the equator: A=(0,0), B=(0,0.01)
    # Point P is slightly North of the segment: P=(0.0009, 0.005)
    # At equator: 0.0009 degrees North is approx 100 meters
    dist, bearing = point_to_segment_distance_meters(0.0009, 0.005, 0.0, 0.0, 0.0, 0.01)
    
    # Bearing of segment going East should be 90
    assert round(bearing) == 90
    
    # Distance should be approx 100 meters (within a small flat-earth projection delta)
    assert 99.0 < dist < 101.0

def test_cross_track_error_multiple_segments():
    # Leader path goes North then East: (0,0) -> (0.01, 0) -> (0.01, 0.01)
    leader_path = [(0.0, 0.0), (0.01, 0.0), (0.01, 0.01)]
    
    # Follower is on the first segment: (0.005, 0)
    cte, bearing = calculate_cross_track_error_and_road_bearing(0.005, 0.0, leader_path)
    assert cte < 1.0
    assert round(bearing) == 0 # First segment goes North
    
    # Follower is 50 meters off the second segment: (0.01, 0.005) is on segment, let's put it at (0.01045, 0.005)
    # 0.00045 degrees North of 0.01 latitude is approx 50 meters
    cte2, bearing2 = calculate_cross_track_error_and_road_bearing(0.01045, 0.005, leader_path)
    assert 48.0 < cte2 < 52.0
    assert round(bearing2) == 90 # Second segment goes East
