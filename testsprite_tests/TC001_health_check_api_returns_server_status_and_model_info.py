import requests

BASE_URL = "http://localhost:8420"

def test_health_check_api_returns_server_status_and_model_info():
    url = f"{BASE_URL}/health"
    try:
        response = requests.get(url, timeout=30)
        assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"
        json_data = response.json()
        assert "status" in json_data, "Response JSON missing 'status'"
        assert json_data["status"] == "running", f"Expected status 'running', got {json_data['status']}"
        assert "provider" in json_data, "Response JSON missing 'provider'"
        assert isinstance(json_data["provider"], str) and json_data["provider"], "Provider should be a non-empty string"
        assert "model" in json_data, "Response JSON missing 'model'"
        assert isinstance(json_data["model"], str) and json_data["model"], "Model should be a non-empty string"
    except requests.exceptions.RequestException as e:
        assert False, f"Request to {url} failed with exception: {e}"

test_health_check_api_returns_server_status_and_model_info()