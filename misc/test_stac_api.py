#!/usr/bin/env python3
"""
STAC API Test Suite using pystac-client
Tests our Aoraki STAC API for compliance and functionality
"""

import sys
import requests
from pystac_client import Client
from pystac_client.exceptions import APIError
import json

# Configuration
API_BASE_URL = "http://localhost:4000/stac/api/v1"
TEST_RESULTS = []

def log_test(test_name, status, message=""):
    """Log test results"""
    status_symbol = "✅" if status else "❌"
    result = f"{status_symbol} {test_name}"
    if message:
        result += f" - {message}"
    print(result)
    TEST_RESULTS.append({"test": test_name, "status": status, "message": message})

def test_api_connectivity():
    """Test basic API connectivity"""
    try:
        response = requests.get(f"{API_BASE_URL}/", timeout=10)
        if response.status_code == 200:
            log_test("API Connectivity", True, f"Status: {response.status_code}")
            return True
        else:
            log_test("API Connectivity", False, f"Status: {response.status_code}")
            return False
    except Exception as e:
        log_test("API Connectivity", False, f"Error: {str(e)}")
        return False

def test_stac_catalog_structure():
    """Test STAC Catalog structure compliance"""
    try:
        response = requests.get(f"{API_BASE_URL}/", timeout=10)
        data = response.json()
        
        # Check required STAC Catalog fields
        required_fields = ["stac_version", "id", "title", "description", "type", "conformsTo", "links"]
        missing_fields = [field for field in required_fields if field not in data]
        
        if not missing_fields:
            log_test("STAC Catalog Structure", True, "All required fields present")
            
            # Check specific values
            if data["type"] == "Catalog":
                log_test("Catalog Type", True, f"Type: {data['type']}")
            else:
                log_test("Catalog Type", False, f"Expected 'Catalog', got: {data['type']}")
                
            if "https://api.stacspec.org/v1.0.0/core" in data["conformsTo"]:
                log_test("STAC Core Conformance", True, "Core conformance declared")
            else:
                log_test("STAC Core Conformance", False, "Core conformance not found")
                
            return True
        else:
            log_test("STAC Catalog Structure", False, f"Missing fields: {missing_fields}")
            return False
            
    except Exception as e:
        log_test("STAC Catalog Structure", False, f"Error: {str(e)}")
        return False

def test_pystac_client():
    """Test using pystac-client library"""
    try:
        # Connect to our API
        catalog = Client.open(f"{API_BASE_URL}/")
        
        # Test basic catalog properties
        log_test("pystac-client Connection", True, f"Title: {catalog.title}")
        
        # Test collections
        collections = list(catalog.get_collections())
        log_test("Collections Access", True, f"Found {len(collections)} collections")
        
        # Test search
        search = catalog.search(limit=5)
        items = list(search.items())
        log_test("Search Functionality", True, f"Found {len(items)} items")
        
        # Test specific collection
        if collections:
            first_collection = collections[0]
            log_test("Collection Details", True, f"Collection: {first_collection.id}")
            
            # Test collection items
            collection_items = list(first_collection.get_items())
            log_test("Collection Items", True, f"Items in {first_collection.id}: {len(collection_items)}")
        
        return True
        
    except APIError as e:
        log_test("pystac-client Connection", False, f"API Error: {str(e)}")
        return False
    except Exception as e:
        log_test("pystac-client Connection", False, f"Error: {str(e)}")
        return False

def test_required_endpoints():
    """Test all required STAC API endpoints"""
    endpoints = [
        ("/", "Landing Page"),
        ("/collections", "Collections List"),
        ("/search", "Search Endpoint"),
        ("/openapi.json", "OpenAPI Spec"),
        ("/docs", "Documentation")
    ]
    
    all_passed = True
    for endpoint, name in endpoints:
        try:
            response = requests.get(f"{API_BASE_URL}{endpoint}", timeout=10)
            if response.status_code == 200:
                log_test(f"Endpoint: {name}", True, f"Status: {response.status_code}")
            else:
                log_test(f"Endpoint: {name}", False, f"Status: {response.status_code}")
                all_passed = False
        except Exception as e:
            log_test(f"Endpoint: {name}", False, f"Error: {str(e)}")
            all_passed = False
    
    return all_passed

def test_search_functionality():
    """Test search functionality with different parameters"""
    try:
        # Basic search
        response = requests.get(f"{API_BASE_URL}/search?limit=3", timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get("type") == "FeatureCollection":
                log_test("Search Response Format", True, f"Found {len(data.get('features', []))} features")
            else:
                log_test("Search Response Format", False, "Not a FeatureCollection")
                return False
        else:
            log_test("Search Response Format", False, f"Status: {response.status_code}")
            return False
        
        # Test with pystac-client search
        catalog = Client.open(f"{API_BASE_URL}/")
        search = catalog.search(limit=3)
        items = list(search.items())
        
        if items:
            log_test("pystac-client Search", True, f"Retrieved {len(items)} items")
            
            # Test item structure
            first_item = items[0]
            if hasattr(first_item, 'id') and hasattr(first_item, 'geometry'):
                log_test("Item Structure", True, f"Item ID: {first_item.id}")
            else:
                log_test("Item Structure", False, "Missing required item fields")
                return False
        else:
            log_test("pystac-client Search", False, "No items found")
            return False
            
        return True
        
    except Exception as e:
        log_test("Search Functionality", False, f"Error: {str(e)}")
        return False

def print_summary():
    """Print test summary"""
    print("\n" + "="*60)
    print("STAC API TEST SUMMARY")
    print("="*60)
    
    passed = sum(1 for result in TEST_RESULTS if result["status"])
    total = len(TEST_RESULTS)
    
    print(f"Total Tests: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {total - passed}")
    print(f"Success Rate: {(passed/total)*100:.1f}%")
    
    if passed == total:
        print("\n🎉 ALL TESTS PASSED! STAC API is working correctly!")
    else:
        print(f"\n⚠️  {total - passed} tests failed. Check the details above.")
    
    print("="*60)

def main():
    """Run all tests"""
    print("🚀 Starting STAC API Tests...")
    print(f"Testing API at: {API_BASE_URL}")
    print("-" * 60)
    
    # Run tests
    test_api_connectivity()
    test_stac_catalog_structure()
    test_required_endpoints()
    test_pystac_client()
    test_search_functionality()
    
    # Print summary
    print_summary()
    
    # Exit with appropriate code
    failed_tests = sum(1 for result in TEST_RESULTS if not result["status"])
    sys.exit(failed_tests)

if __name__ == "__main__":
    main()
