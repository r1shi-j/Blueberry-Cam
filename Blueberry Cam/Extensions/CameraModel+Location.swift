internal import CoreLocation
import Foundation

extension CameraModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            if shouldGeotagLocation {
                shouldGeotagLocation = false
            }
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            if !shouldGeotagLocation {
                shouldGeotagLocation = true
            }
        }
    }
}

extension CameraModel {
    func toggleLocationGeotag() {
        if shouldGeotagLocation {
            let status = locationManager.authorizationStatus
            if status == .denied || status == .restricted {
                errorMessage = "Location access denied. Please enable in Settings."
                showError = true
                shouldGeotagLocation = false
                return
            }
            
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
            locationManager.delegate = nil
            currentLocation = nil
        }
    }
}
