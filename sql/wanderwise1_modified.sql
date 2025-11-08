

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

-- FUNCTION: Calculate Age
CREATE FUNCTION calculate_age(dob DATE)
RETURNS INT
DETERMINISTIC
BEGIN
    RETURN TIMESTAMPDIFF(YEAR, dob, CURDATE());
END//

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
