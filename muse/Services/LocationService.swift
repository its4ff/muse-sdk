//
//  LocationService.swift
//  muse
//
//  Optional location service for capturing where muses are created
//  Works without permission - app functions normally if denied
//

import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject {
    static let shared = LocationService()

    // Current location info (reverse geocoded)
    private(set) var currentLocationString: String?
    private(set) var currentCity: String?
    private(set) var currentCountry: String?

    // Permission state
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var lastLocation: CLLocation?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // City-level is fine
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Public API

    /// Request location permission (call from settings or onboarding)
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    /// Start updating location (call when app becomes active)
    func startUpdating() {
        guard isAuthorized else { return }
        locationManager.startUpdatingLocation()
    }

    /// Stop updating location (call when app goes to background)
    func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }

    /// Get current location string for a muse (returns nil if no permission/location)
    func getCurrentLocationString() -> String? {
        return currentLocationString
    }

    /// Force refresh location and geocode
    func refreshLocation() {
        guard isAuthorized else { return }
        locationManager.requestLocation()
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if isAuthorized {
            startUpdating()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Only geocode if location changed significantly (1km)
        if let last = lastLocation, location.distance(from: last) < 1000 {
            return
        }

        lastLocation = location
        reverseGeocode(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Silent fail - location is optional
        print("[LocationService] Location error: \(error.localizedDescription)")
    }

    // MARK: - Geocoding

    private func reverseGeocode(_ location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self, let placemark = placemarks?.first else {
                return
            }

            Task { @MainActor in
                self.updateLocationFromPlacemark(placemark)
            }
        }
    }

    @MainActor
    private func updateLocationFromPlacemark(_ placemark: CLPlacemark) {
        currentCity = placemark.locality
        currentCountry = placemark.country

        // Format location string
        if let city = placemark.locality {
            if let country = placemark.country {
                // Use country code for common countries, full name for others
                let countryDisplay = formatCountry(country, code: placemark.isoCountryCode)
                currentLocationString = "\(city), \(countryDisplay)".lowercased()
            } else {
                currentLocationString = city.lowercased()
            }
        } else if let area = placemark.administrativeArea {
            if let country = placemark.country {
                let countryDisplay = formatCountry(country, code: placemark.isoCountryCode)
                currentLocationString = "\(area), \(countryDisplay)".lowercased()
            } else {
                currentLocationString = area.lowercased()
            }
        } else if let country = placemark.country {
            currentLocationString = country.lowercased()
        }

        print("[LocationService] Location: \(currentLocationString ?? "unknown")")
    }

    private func formatCountry(_ country: String, code: String?) -> String {
        // Use state/region for US, country code for common countries
        guard let code = code else { return country }

        switch code {
        case "US":
            return "usa"
        case "GB":
            return "uk"
        case "CN":
            return "china"
        case "JP":
            return "japan"
        case "KR":
            return "korea"
        case "DE":
            return "germany"
        case "FR":
            return "france"
        case "IT":
            return "italy"
        case "ES":
            return "spain"
        case "AU":
            return "australia"
        case "CA":
            return "canada"
        case "BR":
            return "brazil"
        case "MX":
            return "mexico"
        case "IN":
            return "india"
        case "SG":
            return "singapore"
        case "HK":
            return "hong kong"
        case "TW":
            return "taiwan"
        default:
            return country.lowercased()
        }
    }
}
