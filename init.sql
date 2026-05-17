CREATE DATABASE IF NOT EXISTS kundenportal;
USE kundenportal;

CREATE TABLE kunden (
    id INT AUTO_INCREMENT PRIMARY KEY,
    vorname VARCHAR(50),
    nachname VARCHAR(50),
    email VARCHAR(100),
    kreditkarte VARCHAR(20),
    kontostand DECIMAL(10,2)
);

INSERT INTO kunden (vorname, nachname, email, kreditkarte, kontostand) VALUES
('Anna', 'Müller', 'anna.mueller@example.com', '4111-XXXX-XXXX-1234', 15420.50),
('Thomas', 'Schmidt', 'thomas.schmidt@example.com', '5500-XXXX-XXXX-5678', 8930.00),
('Lisa', 'Weber', 'lisa.weber@example.com', '3782-XXXX-XXXX-9012', 42100.75),
('Max', 'Fischer', 'max.fischer@example.com', '6011-XXXX-XXXX-3456', 3200.00),
('Sophie', 'Wagner', 'sophie.wagner@example.com', '4000-XXXX-XXXX-7890', 67850.25);
