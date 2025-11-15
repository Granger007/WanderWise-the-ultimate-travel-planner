

DROP DATABASE IF EXISTS WanderWise2;
CREATE DATABASE WanderWise2;
USE WanderWise2;


-- USERS

CREATE TABLE Users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    F_name VARCHAR(50) NOT NULL,
    L_name VARCHAR(50) NOT NULL,
    Name VARCHAR(100) GENERATED ALWAYS AS (CONCAT(F_name, ' ', L_name)) STORED,
    DOB DATE,
    Passport_no VARCHAR(20) UNIQUE,
    Gmail VARCHAR(100) UNIQUE,
    Password VARCHAR(255) NOT NULL,
    Phone_number VARCHAR(20),
    Created_date DATE DEFAULT (CURRENT_DATE),
    Preferences TEXT,
    CONSTRAINT chk_email CHECK (Gmail LIKE '%@%.%')
);

-- LOCATION

CREATE TABLE LOCATION (
    location_id INT PRIMARY KEY AUTO_INCREMENT,
    city_name VARCHAR(100) NOT NULL,
    country_name VARCHAR(100) NOT NULL,
    region_state VARCHAR(100),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    timezone VARCHAR(50),
    currency VARCHAR(10) DEFAULT 'USD',
    activities TEXT,
    CONSTRAINT chk_latitude CHECK (latitude BETWEEN -90 AND 90),
    CONSTRAINT chk_longitude CHECK (longitude BETWEEN -180 AND 180)
);


-- FLIGHT (General flight info only)

CREATE TABLE FLIGHT (
    flight_id INT PRIMARY KEY AUTO_INCREMENT,
    flight_no VARCHAR(20) NOT NULL,
    airline_name VARCHAR(100) NOT NULL,
    dept_airport VARCHAR(100) NOT NULL,
    arr_airport VARCHAR(100) NOT NULL,
    base_price DECIMAL(10,2) NOT NULL,
    flight_duration TIME,
    status VARCHAR(50) DEFAULT 'Scheduled'
);

-- HOTELS (General hotel info only)

CREATE TABLE HOTELS (
    hotel_id INT PRIMARY KEY AUTO_INCREMENT,
    hotel_name VARCHAR(100) NOT NULL,
    location_id INT,
    address VARCHAR(255),
    rating DECIMAL(3,2),
    std_google_review TEXT,
    amenities TEXT,
    price_per_night DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (location_id) REFERENCES LOCATION(location_id) ON DELETE SET NULL,
    CONSTRAINT chk_rating CHECK (rating BETWEEN 0 AND 5)
);


-- TRIP (Personalized user bookings)

CREATE TABLE TRIP (
    trip_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    total_cost DECIMAL(10,2) DEFAULT 0.00,
    
    -- booking details for selected flight & hotel
    flight_id INT,
    hotel_id INT,

    seat_class ENUM('Economy', 'Premium Economy', 'Business', 'First'),
    room_type VARCHAR(50),
    no_of_guests INT DEFAULT 1,
    check_in_date DATE,
    check_out_date DATE,
    booking_ref VARCHAR(50) UNIQUE,
    status VARCHAR(50) DEFAULT 'Pending',

    FOREIGN KEY (user_id) REFERENCES Users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (flight_id) REFERENCES FLIGHT(flight_id) ON DELETE SET NULL,
    FOREIGN KEY (hotel_id) REFERENCES HOTELS(hotel_id) ON DELETE SET NULL,

    CONSTRAINT chk_trip_dates CHECK (end_date >= start_date),
    CONSTRAINT chk_hotel_dates CHECK (
        (check_in_date IS NULL AND check_out_date IS NULL) OR 
        (check_out_date > check_in_date)
    ),
    CONSTRAINT chk_guests CHECK (no_of_guests > 0)
);

-- ACTIVITY

CREATE TABLE ACTIVITY (
    activity_id INT PRIMARY KEY AUTO_INCREMENT,
    trip_id INT,
    location_id INT,
    activity_name VARCHAR(100) NOT NULL,
    description TEXT,
    category VARCHAR(50),
    price DECIMAL(10,2) DEFAULT 0.00,
    duration VARCHAR(50),
    scheduled_date DATE,
    scheduled_time TIME,
    booking_required BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (trip_id) REFERENCES TRIP(trip_id) ON DELETE CASCADE,
    FOREIGN KEY (location_id) REFERENCES LOCATION(location_id) ON DELETE SET NULL
);

-- TRIGGERS: Update trip.total_cost based on hotel & flight & activities

DELIMITER //

CREATE TRIGGER update_trip_total_cost
BEFORE INSERT ON TRIP
FOR EACH ROW
BEGIN
    DECLARE flight_price DECIMAL(10,2);
    DECLARE hotel_price DECIMAL(10,2);

    IF NEW.flight_id IS NOT NULL THEN
        SELECT base_price INTO flight_price FROM FLIGHT WHERE flight_id = NEW.flight_id;
    ELSE
        SET flight_price = 0;
    END IF;

    IF NEW.hotel_id IS NOT NULL THEN
        SELECT price_per_night INTO hotel_price FROM HOTELS WHERE hotel_id = NEW.hotel_id;
    ELSE
        SET hotel_price = 0;
    END IF;

    SET NEW.total_cost = COALESCE(NEW.total_cost,0)
        + flight_price
        + (hotel_price * DATEDIFF(NEW.check_out_date, NEW.check_in_date));
END//

CREATE TRIGGER update_trip_cost_after_activity_insert
AFTER INSERT ON ACTIVITY
FOR EACH ROW
BEGIN
    IF NEW.trip_id IS NOT NULL THEN
        UPDATE TRIP 
        SET total_cost = total_cost + NEW.price
        WHERE trip_id = NEW.trip_id;
    END IF;
END//

CREATE TRIGGER update_trip_cost_after_activity_delete
AFTER DELETE ON ACTIVITY
FOR EACH ROW
BEGIN
    IF OLD.trip_id IS NOT NULL THEN
        UPDATE TRIP 
        SET total_cost = total_cost - OLD.price
        WHERE trip_id = OLD.trip_id;
    END IF;
END//

DELIMITER ;

-- =====================================================
-- SAMPLE DATA
-- =====================================================

INSERT INTO Users (F_name, L_name, DOB, Passport_no, Gmail, Password, Phone_number, Preferences)
VALUES
('John', 'Doe', '1990-05-15', 'P1234567', 'john.doe@gmail.com', 'hashedpass123', '9876543210', 'Adventure, Beach'),
('Ava', 'Smith', '1988-02-10', 'P2233445', 'ava.smith@gmail.com', 'hashpass987', '9898989898', 'Cultural, Food'),
('Raj', 'Kumar', '1995-09-25', 'P9988776', 'raj.kumar@gmail.com', 'hashpass456', '9123456780', 'Hill stations');

INSERT INTO LOCATION (city_name, country_name, region_state, latitude, longitude, timezone, currency, activities)
VALUES
('Paris', 'France', 'Île-de-France', 48.8566, 2.3522, 'GMT+1', 'EUR', 'Eiffel Tower, Museums, Cafes'),
('Tokyo', 'Japan', 'Kanto', 35.6762, 139.6503, 'GMT+9', 'JPY', 'Temples, Food Tours, Anime'),
('New York', 'USA', 'New York', 40.7128, -74.0060, 'GMT-5', 'USD', 'Broadway, Parks, Museums');

INSERT INTO HOTELS (hotel_name, location_id, address, rating, amenities, price_per_night)
VALUES
('Eiffel Stay', 1, '123 Rue de Paris, France', 4.5, 'WiFi, Breakfast, Gym', 180.00),
('Tokyo Serenity', 2, '5-2-1 Shibuya, Tokyo', 4.7, 'WiFi, Spa, Pool', 210.00),
('Central Inn', 3, '9th Avenue, Manhattan', 4.2, 'WiFi, Bar, Parking', 150.00);

INSERT INTO FLIGHT (flight_no, airline_name, dept_airport, arr_airport, base_price, flight_duration)
VALUES
('AF178', 'Air France', 'JFK Airport', 'CDG Airport', 650.00, '07:50:00'),
('JL32', 'Japan Airlines', 'LAX Airport', 'HND Airport', 1200.00, '11:00:00'),
('UA55', 'United Airlines', 'LHR Airport', 'JFK Airport', 800.00, '08:00:00');

INSERT INTO TRIP (user_id, start_date, end_date, flight_id, hotel_id, seat_class, room_type, no_of_guests, check_in_date, check_out_date, booking_ref)
VALUES
(1, '2025-03-01', '2025-03-10', 1, 1, 'Economy', 'Deluxe', 2, '2025-03-01', '2025-03-05', 'BK1001'),
(2, '2025-04-05', '2025-04-15', 2, 2, 'Business', 'Suite', 1, '2025-04-06', '2025-04-10', 'BK1002'),
(3, '2025-05-10', '2025-05-20', 3, 3, 'Premium Economy', 'Standard', 2, '2025-05-10', '2025-05-14', 'BK1003');

INSERT INTO ACTIVITY (trip_id, location_id, activity_name, description, category, price, duration, scheduled_date, scheduled_time, booking_required)
VALUES
(1, 1, 'Eiffel Tower Tour', 'Visit the iconic Eiffel Tower and enjoy city views.', 'Sightseeing', 75.00, '2 hours', '2025-03-02', '10:00:00', TRUE),
(2, 2, 'Tokyo Food Tour', 'Experience Japan’s finest cuisine.', 'Food', 120.00, '4 hours', '2025-04-07', '12:00:00', TRUE),
(3, 3, 'Central Park Walk', 'Relaxing walk through Central Park.', 'Nature', 0.00, '2 hours', '2025-05-13', '08:00:00', FALSE);

-- =====================================================
-- VIEW: SEARCH_VIEW
-- =====================================================

CREATE OR REPLACE VIEW SEARCH_VIEW AS
SELECT 
    f.flight_id AS item_id,
    f.flight_no AS name,
    'Flight' AS category,
    f.base_price AS price,
    f.dept_airport AS location,
    NULL AS start_time,
    NULL AS end_time
FROM FLIGHT f
UNION ALL
SELECT 
    h.hotel_id AS item_id,
    h.hotel_name AS name,
    'Hotel' AS category,
    h.price_per_night AS price,
    l.city_name AS location,
    NULL AS start_time,
    NULL AS end_time
FROM HOTELS h
JOIN LOCATION l ON h.location_id = l.location_id
UNION ALL
SELECT 
    a.activity_id AS item_id,
    a.activity_name AS name,
    'Activity' AS category,
    a.price,
    l.city_name AS location,
    a.scheduled_date AS start_time,
    NULL AS end_time
FROM ACTIVITY a
JOIN LOCATION l ON a.location_id = l.location_id;

SELECT '✅ WanderWise2 refactored database created successfully.' AS Status;

-- TRIGGERS: Update Trip Total Cost

DELIMITER //

CREATE TRIGGER update_trip_cost_after_flight_insert
AFTER INSERT ON FLIGHT
FOR EACH ROW
BEGIN
    IF NEW.trip_id IS NOT NULL THEN
        UPDATE TRIP 
        SET total_cost = total_cost + NEW.price 
        WHERE trip_id = NEW.trip_id;
    END IF;
END//

CREATE TRIGGER update_trip_cost_after_flight_update
AFTER UPDATE ON FLIGHT
FOR EACH ROW
BEGIN
    IF NEW.trip_id IS NOT NULL THEN
        UPDATE TRIP 
        SET total_cost = total_cost - OLD.price + NEW.price 
        WHERE trip_id = NEW.trip_id;
    END IF;
END//

CREATE TRIGGER update_trip_cost_after_flight_delete
AFTER DELETE ON FLIGHT
FOR EACH ROW
BEGIN
    IF OLD.trip_id IS NOT NULL THEN
        UPDATE TRIP 
        SET total_cost = total_cost - OLD.price 
        WHERE trip_id = OLD.trip_id;
    END IF;
END//

-- -- FUNCTION: Calculate Age
-- CREATE FUNCTION calculate_age(dob DATE)
-- RETURNS INT
-- DETERMINISTIC
-- BEGIN
--     RETURN TIMESTAMPDIFF(YEAR, dob, CURDATE());
-- END//

-- FUNCTION: Calculate trip duration
DELIMITER $$

CREATE FUNCTION calculate_nights(check_in DATE, check_out DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN DATEDIFF(check_out, check_in);
END $$

DELIMITER ;


-- PROCEDURE: Get Trip Summary
CREATE PROCEDURE get_trip_summary(IN p_trip_id INT)
BEGIN
    SELECT 
        t.trip_id,
        u.Name AS user_name,
        t.start_date,
        t.end_date,
        DATEDIFF(t.end_date, t.start_date) AS duration_days,
        t.total_cost,
        COUNT(DISTINCT f.flight_id) AS num_flights,
        COUNT(DISTINCT h.Hotel_ID) AS num_hotels,
        COUNT(DISTINCT a.activity_id) AS num_activities
    FROM TRIP t
    JOIN Users u ON t.user_id = u.user_id
    LEFT JOIN FLIGHT f ON t.trip_id = f.trip_id
    LEFT JOIN HOTELS h ON t.trip_id = h.Trip_ID
    LEFT JOIN ACTIVITY a ON t.trip_id = a.trip_id
    WHERE t.trip_id = p_trip_id
    GROUP BY t.trip_id, u.Name, t.start_date, t.end_date, t.total_cost;
END//

DELIMITER ;


-- POPULATE ADMIN FLIGHT DATA

-- INSERT INTO Flight (flight_no, airline_name, dept_airport, arr_airport, base_price, flight_duration, status)
-- VALUES
-- -- 1. To Cape Town
-- ('BA059', 'British Airways', 'London Heathrow (LHR)', 'Cape Town International (CPT)', 950.00, '11:30:00', 'Scheduled'),

-- -- 2. To Vancouver
-- ('AC855', 'Air Canada', 'London Heathrow (LHR)', 'Vancouver International (YVR)', 780.00, '09:45:00', 'Scheduled'),

-- -- 3. To London
-- ('UA901', 'United Airlines', 'San Francisco International (SFO)', 'London Heathrow (LHR)', 890.00, '10:30:00', 'Scheduled'),

-- -- 4. To Los Angeles
-- ('DL405', 'Delta Air Lines', 'New York JFK (JFK)', 'Los Angeles International (LAX)', 320.00, '06:15:00', 'Scheduled'),

-- -- 5. To Dubai
-- ('EK202', 'Emirates', 'New York JFK (JFK)', 'Dubai International (DXB)', 1100.00, '12:45:00', 'Scheduled'),

-- -- 6. To Singapore
-- ('SQ317', 'Singapore Airlines', 'London Heathrow (LHR)', 'Singapore Changi (SIN)', 1050.00, '13:15:00', 'Scheduled'),

-- -- 7. To Bangkok
-- ('TG911', 'Thai Airways', 'London Heathrow (LHR)', 'Suvarnabhumi Airport (BKK)', 960.00, '11:50:00', 'Scheduled'),

-- -- 8. To Hong Kong
-- ('CX255', 'Cathay Pacific', 'London Heathrow (LHR)', 'Hong Kong International (HKG)', 980.00, '11:45:00', 'Scheduled'),

-- -- 9. To Barcelona
-- ('IB3159', 'Iberia', 'Madrid-Barajas (MAD)', 'Barcelona El Prat (BCN)', 120.00, '01:10:00', 'Scheduled'),

-- -- 10. To Istanbul
-- ('TK1980', 'Turkish Airlines', 'London Heathrow (LHR)', 'Istanbul Airport (IST)', 350.00, '03:50:00', 'Scheduled'),

-- -- 11. To Rio de Janeiro
-- ('LA8065', 'LATAM Airlines', 'São Paulo Guarulhos (GRU)', 'Rio de Janeiro-Galeão (GIG)', 180.00, '01:05:00', 'Scheduled'),

-- -- 12. To Cairo
-- ('MS778', 'EgyptAir', 'London Heathrow (LHR)', 'Cairo International (CAI)', 540.00, '05:15:00', 'Scheduled'),

-- -- 13. To Venice
-- ('AZ146', 'ITA Airways', 'Rome Fiumicino (FCO)', 'Venice Marco Polo (VCE)', 110.00, '01:00:00', 'Scheduled'),

-- -- 14. To San Francisco
-- ('AA177', 'American Airlines', 'New York JFK (JFK)', 'San Francisco International (SFO)', 340.00, '06:20:00', 'Scheduled'),

-- -- 15. To Athens
-- ('A3805', 'Aegean Airlines', 'London Heathrow (LHR)', 'Athens International (ATH)', 300.00, '03:40:00', 'Scheduled'),

-- -- 16. To Amsterdam
-- ('KL1006', 'KLM Royal Dutch Airlines', 'London Heathrow (LHR)', 'Amsterdam Schiphol (AMS)', 140.00, '01:15:00', 'Scheduled'),

-- -- 17. To Las Vegas
-- ('WN2378', 'Southwest Airlines', 'Los Angeles International (LAX)', 'McCarran International (LAS)', 95.00, '01:10:00', 'Scheduled'),

-- -- 18. To Buenos Aires
-- ('AR1301', 'Aerolíneas Argentinas', 'Miami International (MIA)', 'Buenos Aires Ezeiza (EZE)', 720.00, '09:00:00', 'Scheduled'),

-- -- 19. To Reykjavik
-- ('FI455', 'Icelandair', 'London Heathrow (LHR)', 'Keflavik International (KEF)', 280.00, '03:00:00', 'Scheduled'),

-- -- 20. To Lisbon
-- ('TP1337', 'TAP Air Portugal', 'London Heathrow (LHR)', 'Lisbon Humberto Delgado (LIS)', 190.00, '02:45:00', 'Scheduled');



--POPULATE ADMIN HOTEL DATA
-- INSERT INTO Hotel (hotel_name, location_id, address, rating, std_google_review, amenities, price_per_night) VALUES
-- ('The Ritz London', 3, '150 Piccadilly, St. James\'s, London W1J 9BR, United Kingdom', 4.8, 'Elegant and luxurious hotel offering top-class dining and impeccable service in the heart of London.', 'Free WiFi, Spa, Fine Dining, Concierge, Fitness Center, Bar', 850.00),

-- ('Beverly Hills Hotel', 4, '9641 Sunset Blvd, Beverly Hills, CA 90210, United States', 4.7, 'Iconic “Pink Palace” known for luxury suites, palm gardens, and celebrity history.', 'Pool, Spa, Restaurant, Valet Parking, Pet Friendly, Bar', 950.00),

-- ('Burj Al Arab Jumeirah', 5, 'Jumeirah St - Dubai, United Arab Emirates', 4.8, 'World-famous sail-shaped hotel offering unparalleled luxury and service.', 'Private Beach, Butler Service, Spa, Pool, Helipad, Restaurant', 1800.00),

-- ('Marina Bay Sands', 6, '10 Bayfront Ave, Singapore 018956', 4.6, 'Famous for its rooftop infinity pool and panoramic city views.', 'Infinity Pool, Casino, Restaurants, Gym, Spa, Shopping Mall', 600.00),

-- ('Mandarin Oriental Bangkok', 7, '48 Oriental Ave, Bang Rak, Bangkok 10500, Thailand', 4.8, 'Historic riverside hotel offering elegant suites and legendary Thai hospitality.', 'Spa, Pool, Riverside Dining, Fitness Center, Bar', 500.00),

-- ('The Peninsula Hong Kong', 8, 'Salisbury Road, Tsim Sha Tsui, Kowloon, Hong Kong', 4.7, 'Classic luxury hotel offering Rolls-Royce transfers and harbor views.', 'Spa, Indoor Pool, Afternoon Tea, Fitness Center, Limousine Service', 750.00),

-- ('Hotel Arts Barcelona', 9, 'Carrer de la Marina, 19–21, 08005 Barcelona, Spain', 4.6, 'Modern beachfront hotel known for sea views and exceptional dining.', 'Pool, Spa, Restaurant, Gym, Sea View Rooms, Bar', 550.00),

-- ('Four Seasons Istanbul at the Bosphorus', 10, 'Çırağan Cd. No:28, Beşiktaş, İstanbul, Türkiye', 4.9, 'Palatial hotel along the Bosphorus with Ottoman-inspired design.', 'Spa, Waterfront Dining, Pool, Gym, Bar, Concierge', 700.00),

-- ('Copacabana Palace', 11, 'Avenida Atlântica, 1702 - Copacabana, Rio de Janeiro, Brazil', 4.8, 'Historic beachfront hotel symbolizing Rio’s glamour and elegance.', 'Beach Access, Pool, Spa, Restaurants, Bar, Fitness Center', 650.00),

-- ('The Nile Ritz-Carlton', 12, '1113 Corniche El Nil, Cairo, Egypt', 4.7, 'Luxury hotel overlooking the Nile with exceptional dining and service.', 'Pool, Spa, Restaurant, Bar, Gym, Business Center', 400.00),

-- ('The Gritti Palace', 13, 'Campo Santa Maria del Giglio, 2467, 30124 Venezia VE, Italy', 4.8, 'Venetian palace turned hotel offering grand canal views and timeless luxury.', 'Restaurant, Bar, Spa, Butler Service, Pet Friendly', 900.00),

-- ('Fairmont San Francisco', 14, '950 Mason St, San Francisco, CA 94108, United States', 4.6, 'Historic Nob Hill hotel offering panoramic city and bay views.', 'Spa, Gym, Bar, Conference Rooms, Concierge', 500.00),

-- ('Hotel Grande Bretagne', 15, '1 Vasileos Georgiou A, Syntagma Square, Athens 105 64, Greece', 4.8, 'Athenian landmark with views of the Acropolis and exceptional service.', 'Spa, Rooftop Pool, Restaurant, Bar, Gym', 550.00),

-- ('W Amsterdam', 16, 'Spuistraat 175, 1012 VN Amsterdam, Netherlands', 4.4, 'Trendy and modern hotel offering rooftop views and contemporary design.', 'Rooftop Pool, Bar, Gym, Spa, Pet Friendly', 450.00),

-- ('Bellagio Hotel & Casino', 17, '3600 Las Vegas Blvd S, Las Vegas, NV 89109, United States', 4.7, 'World-renowned Las Vegas resort known for its fountain show and luxury casino.', 'Casino, Pool, Spa, Fine Dining, Entertainment, Bar', 600.00);



--POPULATE ADMIN LOCATION DATA 
-- INSERT INTO Location (city_name, country_name, region_state, latitude, longitude, timezone, currency, activities) VALUES
-- ('Cape Town', 'South Africa', 'Western Cape', -33.9249, 18.4241, 'UTC+2', 'ZAR', 'Table Mountain hiking, Cape Point tour, Robben Island visit, wine tasting in Stellenbosch'),
-- ('Vancouver', 'Canada', 'British Columbia', 49.2827, -123.1207, 'UTC-8 (Pacific Time)', 'CAD', 'Stanley Park cycling, Grouse Mountain, Granville Island, whale watching'),
-- ('London', 'United Kingdom', 'England', 51.5074, -0.1278, 'UTC+0', 'GBP', 'Buckingham Palace, London Eye, Tower of London, Big Ben'),
-- ('Los Angeles', 'United States', 'California', 34.0522, -118.2437, 'UTC-8 (Pacific Time)', 'USD', 'Hollywood, Santa Monica Pier, Universal Studios, Beverly Hills'),
-- ('Dubai', 'United Arab Emirates', 'Dubai Emirate', 25.276987, 55.296249, 'UTC+4', 'AED', 'Burj Khalifa, Desert Safari, Dubai Mall, Palm Jumeirah'),
-- ('Singapore', 'Singapore', NULL, 1.3521, 103.8198, 'UTC+8', 'SGD', 'Marina Bay Sands, Gardens by the Bay, Sentosa Island, Orchard Road'),
-- ('Bangkok', 'Thailand', 'Bangkok Metropolitan Region', 13.7563, 100.5018, 'UTC+7', 'THB', 'Grand Palace, Floating Markets, Wat Arun, street food tours'),
-- ('Hong Kong', 'China (Special Administrative Region)', NULL, 22.3193, 114.1694, 'UTC+8', 'HKD', 'Victoria Peak, Disneyland, Avenue of Stars, Star Ferry'),
-- ('Barcelona', 'Spain', 'Catalonia', 41.3851, 2.1734, 'UTC+1', 'EUR', 'Sagrada Família, Park Güell, La Rambla, beach walks'),
-- ('Istanbul', 'Turkey', 'Marmara Region', 41.0082, 28.9784, 'UTC+3', 'TRY', 'Hagia Sophia, Blue Mosque, Grand Bazaar, Bosphorus cruise'),
-- ('Rio de Janeiro', 'Brazil', 'Rio de Janeiro', -22.9068, -43.1729, 'UTC-3', 'BRL', 'Christ the Redeemer, Copacabana Beach, Sugarloaf Mountain, Carnival'),
-- ('Cairo', 'Egypt', 'Cairo Governorate', 30.0444, 31.2357, 'UTC+2', 'EGP', 'Pyramids of Giza, Egyptian Museum, Nile River cruise, Khan el-Khalili bazaar'),
-- ('Venice', 'Italy', 'Veneto', 45.4408, 12.3155, 'UTC+1', 'EUR', 'Gondola rides, St. Mark’s Square, Doge’s Palace, Rialto Bridge'),
-- ('San Francisco', 'United States', 'California', 37.7749, -122.4194, 'UTC-8 (Pacific Time)', 'USD', 'Golden Gate Bridge, Alcatraz Island, cable cars, Fisherman’s Wharf'),
-- ('Athens', 'Greece', 'Attica', 37.9838, 23.7275, 'UTC+2', 'EUR', 'Acropolis, Parthenon, Plaka district, ancient ruins'),
-- ('Amsterdam', 'Netherlands', 'North Holland', 52.3676, 4.9041, 'UTC+1', 'EUR', 'Canal cruises, Anne Frank House, Van Gogh Museum, cycling tours'),
-- ('Las Vegas', 'United States', 'Nevada', 36.1699, -115.1398, 'UTC-8 (Pacific Time)', 'USD', 'Casinos, live shows, The Strip, Grand Canyon day trips'),
-- ('Buenos Aires', 'Argentina', 'Buenos Aires Autonomous City', -34.6037, -58.3816, 'UTC-3', 'ARS', 'Tango shows, Recoleta Cemetery, San Telmo market, steakhouse dining'),
-- ('Reykjavik', 'Iceland', 'Capital Region', 64.1355, -21.8954, 'UTC+0', 'ISK', 'Northern Lights watching, Blue Lagoon, whale watching, Golden Circle tour'),
-- ('Lisbon', 'Portugal', 'Lisbon District', 38.7169, -9.1399, 'UTC+0', 'EUR', 'Tram 28 ride, Alfama district tour, Belem Tower, Fado music nights');
