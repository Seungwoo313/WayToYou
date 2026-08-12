import Foundation

struct CurrentCityWeather: Equatable, Sendable {
    let temperatureCelsius: Double
    let weatherCode: Int
    let isDay: Bool

    var symbolName: String {
        switch weatherCode {
        case 0:
            isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:
            isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:
            "cloud.fill"
        case 45, 48:
            "cloud.fog.fill"
        case 51, 53, 55, 56, 57:
            "cloud.drizzle.fill"
        case 61, 63, 65, 80, 81, 82:
            "cloud.rain.fill"
        case 66, 67:
            "cloud.sleet.fill"
        case 71, 73, 75, 77, 85, 86:
            "cloud.snow.fill"
        case 95, 96, 99:
            "cloud.bolt.rain.fill"
        default:
            "cloud.fill"
        }
    }

    var conditionDescription: String {
        switch weatherCode {
        case 0: "맑음"
        case 1, 2: "구름 조금"
        case 3: "흐림"
        case 45, 48: "안개"
        case 51, 53, 55, 56, 57: "이슬비"
        case 61, 63, 65, 66, 67, 80, 81, 82: "비"
        case 71, 73, 75, 77, 85, 86: "눈"
        case 95, 96, 99: "뇌우"
        default: "날씨"
        }
    }
}

struct WeatherService {
    private struct ForecastResponse: Decodable {
        let current: CurrentResponse
    }

    private struct CurrentResponse: Decodable {
        let temperature: Double
        let weatherCode: Int
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature = "temperature_2m"
            case weatherCode = "weather_code"
            case isDay = "is_day"
        }
    }

    func currentWeather(for city: CoupleCity) async throws -> CurrentCityWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)),
            URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,weather_code,is_day"
            ),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let current = try JSONDecoder().decode(ForecastResponse.self, from: data).current
        return CurrentCityWeather(
            temperatureCelsius: current.temperature,
            weatherCode: current.weatherCode,
            isDay: current.isDay == 1
        )
    }
}
