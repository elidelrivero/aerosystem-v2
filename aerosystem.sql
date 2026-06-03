-- ============================================================
-- AeroSystem v2 — Base de datos completa con vuelos dinámicos
-- ============================================================

DROP DATABASE IF EXISTS aerosystemDB;
CREATE DATABASE aerosystemDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE aerosystemDB;

-- --------------------------------------------------------------------
-- CONFIGURACIÓN
-- --------------------------------------------------------------------
CREATE TABLE politica_cancelacion (
    id_politica    INT AUTO_INCREMENT PRIMARY KEY,
    dias_antes     INT NOT NULL DEFAULT 2,
    activo         BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_creacion DATETIME DEFAULT NOW()
);
INSERT INTO politica_cancelacion (dias_antes, activo) VALUES (2, TRUE);

-- --------------------------------------------------------------------
-- USUARIOS
-- --------------------------------------------------------------------
CREATE TABLE usuario (
    id_usuario     INT AUTO_INCREMENT PRIMARY KEY,
    nombre         VARCHAR(100) NOT NULL,
    correo         VARCHAR(150) NOT NULL UNIQUE,
    fecha_registro DATETIME DEFAULT NOW()
);

-- --------------------------------------------------------------------
-- CATÁLOGOS
-- --------------------------------------------------------------------
CREATE TABLE aerolinea (
    id_aerolinea INT AUTO_INCREMENT PRIMARY KEY,
    nombre       VARCHAR(100),
    codigo       VARCHAR(10),
    pais_origen  VARCHAR(50)
);

CREATE TABLE tipo_avion (
    id_tipo_avion INT AUTO_INCREMENT PRIMARY KEY,
    modelo        VARCHAR(100),
    capacidad     INT,
    fabricante    VARCHAR(50)
);

CREATE TABLE avion (
    id_avion      INT AUTO_INCREMENT PRIMARY KEY,
    id_aerolinea  INT,
    id_tipo_avion INT,
    matricula     VARCHAR(20),
    FOREIGN KEY (id_aerolinea)  REFERENCES aerolinea(id_aerolinea),
    FOREIGN KEY (id_tipo_avion) REFERENCES tipo_avion(id_tipo_avion)
);

CREATE TABLE piloto (
    id_piloto         INT AUTO_INCREMENT PRIMARY KEY,
    nombre            VARCHAR(100),
    licencia          VARCHAR(30),
    anios_experiencia INT,
    id_aerolinea      INT,
    FOREIGN KEY (id_aerolinea) REFERENCES aerolinea(id_aerolinea)
);

CREATE TABLE tipo_asiento (
    id_tipo_asiento       INT AUTO_INCREMENT PRIMARY KEY,
    descripcion           VARCHAR(50),
    porcentaje_incremento DECIMAL(5,2),
    precio_base           DECIMAL(10,2) DEFAULT 1500.00
);

-- --------------------------------------------------------------------
-- DESTINOS
-- --------------------------------------------------------------------
CREATE TABLE destino (
    id_destino  INT AUTO_INCREMENT PRIMARY KEY,
    ciudad      VARCHAR(100) NOT NULL,
    pais        VARCHAR(100) NOT NULL,
    codigo_iata VARCHAR(3),
    descripcion VARCHAR(255),
    imagen_url  VARCHAR(500)
);

-- --------------------------------------------------------------------
-- VUELOS
-- --------------------------------------------------------------------
CREATE TABLE vuelo (
    id_vuelo            INT AUTO_INCREMENT PRIMARY KEY,
    id_avion            INT,
    id_piloto           INT,
    id_origen           INT,
    id_destino          INT,
    origen              VARCHAR(100),
    destino             VARCHAR(100),
    fecha_salida        DATE,
    hora_salida         TIME,
    hora_llegada        TIME,
    duracion_min        INT,
    precio_base         DECIMAL(10,2) DEFAULT 1500.00,
    vuelo_internacional BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (id_avion)   REFERENCES avion(id_avion),
    FOREIGN KEY (id_piloto)  REFERENCES piloto(id_piloto),
    FOREIGN KEY (id_origen)  REFERENCES destino(id_destino),
    FOREIGN KEY (id_destino) REFERENCES destino(id_destino)
);

CREATE TABLE inventario_asientos (
    id_inventario        INT AUTO_INCREMENT PRIMARY KEY,
    id_vuelo             INT,
    id_tipo_asiento      INT,
    asientos_totales     INT,
    asientos_disponibles INT,
    FOREIGN KEY (id_vuelo)        REFERENCES vuelo(id_vuelo),
    FOREIGN KEY (id_tipo_asiento) REFERENCES tipo_asiento(id_tipo_asiento),
    UNIQUE KEY (id_vuelo, id_tipo_asiento)
);

-- --------------------------------------------------------------------
-- RESERVACIONES Y PAGOS
-- --------------------------------------------------------------------
CREATE TABLE reservacion (
    id_reservacion   INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario       INT NOT NULL,
    id_vuelo         INT NOT NULL,
    id_tipo_asiento  INT NOT NULL,
    fecha_reserva    DATETIME DEFAULT NOW(),
    estado           ENUM('pendiente','confirmada','cancelada','expirada') DEFAULT 'pendiente',
    fecha_expiracion DATETIME,
    FOREIGN KEY (id_usuario)      REFERENCES usuario(id_usuario),
    FOREIGN KEY (id_vuelo)        REFERENCES vuelo(id_vuelo),
    FOREIGN KEY (id_tipo_asiento) REFERENCES tipo_asiento(id_tipo_asiento)
);

CREATE TABLE boleto (
    id_boleto       INT AUTO_INCREMENT PRIMARY KEY,
    id_usuario      INT NOT NULL,
    id_vuelo        INT NOT NULL,
    id_tipo_asiento INT NOT NULL,
    id_reservacion  INT NOT NULL,
    codigo_boleto   VARCHAR(20) UNIQUE,
    fecha_compra    DATETIME DEFAULT NOW(),
    costo_base      DECIMAL(10,2),
    costo_final     DECIMAL(10,2),
    FOREIGN KEY (id_usuario)      REFERENCES usuario(id_usuario),
    FOREIGN KEY (id_vuelo)        REFERENCES vuelo(id_vuelo),
    FOREIGN KEY (id_tipo_asiento) REFERENCES tipo_asiento(id_tipo_asiento),
    FOREIGN KEY (id_reservacion)  REFERENCES reservacion(id_reservacion)
);

CREATE TABLE cancelacion (
    id_cancelacion    INT AUTO_INCREMENT PRIMARY KEY,
    id_reservacion    INT,
    fecha_cancelacion DATETIME DEFAULT NOW(),
    motivo            VARCHAR(255),
    FOREIGN KEY (id_reservacion) REFERENCES reservacion(id_reservacion)
);

CREATE TABLE pago (
    id_pago         INT AUTO_INCREMENT PRIMARY KEY,
    id_reservacion  INT,
    monto           DECIMAL(10,2),
    metodo_pago     VARCHAR(50),
    fecha_pago      DATETIME DEFAULT NOW(),
    aprobado        BOOLEAN DEFAULT FALSE,
    tipo_movimiento ENUM('pago','reembolso') DEFAULT 'pago',
    FOREIGN KEY (id_reservacion) REFERENCES reservacion(id_reservacion)
);

-- --------------------------------------------------------------------
-- TRIGGERS
-- --------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_before_reservacion
BEFORE INSERT ON reservacion
FOR EACH ROW
BEGIN
    IF EXISTS (
        SELECT 1 FROM reservacion
        WHERE id_usuario = NEW.id_usuario
          AND id_vuelo   = NEW.id_vuelo
          AND estado IN ('pendiente','confirmada')
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Ya tienes una reservacion activa para este vuelo';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM inventario_asientos
        WHERE id_vuelo        = NEW.id_vuelo
          AND id_tipo_asiento = NEW.id_tipo_asiento
          AND asientos_disponibles > 0
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No hay asientos disponibles para esta clase';
    END IF;

    IF NEW.fecha_expiracion IS NULL THEN
        SET NEW.fecha_expiracion = DATE_ADD(NOW(), INTERVAL 24 HOUR);
    END IF;
END$$

CREATE TRIGGER trg_after_reservacion
AFTER INSERT ON reservacion
FOR EACH ROW
BEGIN
    UPDATE inventario_asientos
    SET asientos_disponibles = asientos_disponibles - 1
    WHERE id_vuelo        = NEW.id_vuelo
      AND id_tipo_asiento = NEW.id_tipo_asiento;
END$$

CREATE TRIGGER trg_after_boleto
AFTER INSERT ON boleto
FOR EACH ROW
BEGIN
    UPDATE reservacion
    SET estado = 'confirmada'
    WHERE id_reservacion = NEW.id_reservacion;
END$$

DELIMITER ;

-- --------------------------------------------------------------------
-- EVENTOS
-- --------------------------------------------------------------------
SET GLOBAL event_scheduler = ON;

DELIMITER $$

CREATE EVENT ev_expirar_reservaciones
ON SCHEDULE EVERY 1 HOUR
DO
BEGIN
    UPDATE reservacion r
    JOIN inventario_asientos ia
        ON ia.id_vuelo = r.id_vuelo AND ia.id_tipo_asiento = r.id_tipo_asiento
    SET r.estado = 'expirada',
        ia.asientos_disponibles = ia.asientos_disponibles + 1
    WHERE r.estado = 'pendiente'
      AND r.fecha_expiracion < NOW();
END$$

DELIMITER ;

-- --------------------------------------------------------------------
-- STORED PROCEDURES
-- --------------------------------------------------------------------
DELIMITER $$

-- Login / registro automático
CREATE PROCEDURE sp_login_usuario(
    IN p_nombre VARCHAR(100),
    IN p_correo VARCHAR(150)
)
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE correo = p_correo) THEN
        INSERT INTO usuario (nombre, correo) VALUES (p_nombre, p_correo);
    ELSE
        UPDATE usuario SET nombre = p_nombre WHERE correo = p_correo;
    END IF;
    SELECT id_usuario, nombre, correo FROM usuario WHERE correo = p_correo;
END$$

-- Búsqueda dinámica: crea el vuelo si no existe para esa ruta y fecha
CREATE PROCEDURE sp_buscar_vuelos(
    IN p_origen  VARCHAR(100),
    IN p_destino VARCHAR(100),
    IN p_fecha   DATE
)
BEGIN
    DECLARE v_id_origen     INT DEFAULT NULL;
    DECLARE v_id_destino    INT DEFAULT NULL;
    DECLARE v_id_avion      INT;
    DECLARE v_id_piloto     INT;
    DECLARE v_precio        DECIMAL(10,2);
    DECLARE v_duracion      INT;
    DECLARE v_hora_sal      TIME;
    DECLARE v_hora_llg      TIME;
    DECLARE v_internacional BOOLEAN;
    DECLARE v_nuevo_vuelo   INT;

    -- Validar fecha futura
    IF p_fecha <= CURDATE() THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La fecha debe ser a partir de manana';
    END IF;

    -- Buscar IDs de ciudades
    SELECT id_destino INTO v_id_origen  FROM destino WHERE ciudad = p_origen  LIMIT 1;
    SELECT id_destino INTO v_id_destino FROM destino WHERE ciudad = p_destino LIMIT 1;

    -- Si alguna ciudad no existe, salir sin resultados
    IF v_id_origen IS NULL OR v_id_destino IS NULL THEN
        SELECT NULL WHERE FALSE;
    ELSE
        -- Crear vuelos si no existen para esa ruta y fecha
        IF NOT EXISTS (
            SELECT 1 FROM vuelo
            WHERE origen = p_origen
              AND destino = p_destino
              AND fecha_salida = p_fecha
        ) THEN
            -- Avión y piloto aleatorios
            SELECT id_avion  INTO v_id_avion  FROM avion  ORDER BY RAND() LIMIT 1;
            SELECT id_piloto INTO v_id_piloto FROM piloto ORDER BY RAND() LIMIT 1;

            -- Precio y duración según si es internacional
            SET v_internacional = (
                SELECT d1.pais != d2.pais
                FROM destino d1, destino d2
                WHERE d1.ciudad = p_origen AND d2.ciudad = p_destino
            );

            IF v_internacional THEN
                SET v_precio   = ROUND(3000 + (RAND() * 4000), -2);
                SET v_duracion = 180 + FLOOR(RAND() * 300);
            ELSE
                SET v_precio   = ROUND(800 + (RAND() * 1500), -2);
                SET v_duracion = 45  + FLOOR(RAND() * 120);
            END IF;

            -- Vuelo de mañana (07:00)
            SET v_hora_sal = '07:00:00';
            SET v_hora_llg = ADDTIME('07:00:00', SEC_TO_TIME(v_duracion * 60));

            INSERT INTO vuelo (
                id_avion, id_piloto, id_origen, id_destino,
                origen, destino, fecha_salida,
                hora_salida, hora_llegada, duracion_min,
                precio_base, vuelo_internacional
            ) VALUES (
                v_id_avion, v_id_piloto, v_id_origen, v_id_destino,
                p_origen, p_destino, p_fecha,
                v_hora_sal, v_hora_llg, v_duracion,
                v_precio, v_internacional
            );

            SET v_nuevo_vuelo = LAST_INSERT_ID();

            INSERT INTO inventario_asientos (id_vuelo, id_tipo_asiento, asientos_totales, asientos_disponibles) VALUES
                (v_nuevo_vuelo, 1, 150, 150),
                (v_nuevo_vuelo, 2,  30,  30),
                (v_nuevo_vuelo, 3,  10,  10);

            -- Vuelo de tarde (15:00) — 10% más barato
            SET v_hora_sal = '15:00:00';
            SET v_hora_llg = ADDTIME('15:00:00', SEC_TO_TIME(v_duracion * 60));

            INSERT INTO vuelo (
                id_avion, id_piloto, id_origen, id_destino,
                origen, destino, fecha_salida,
                hora_salida, hora_llegada, duracion_min,
                precio_base, vuelo_internacional
            ) VALUES (
                v_id_avion, v_id_piloto, v_id_origen, v_id_destino,
                p_origen, p_destino, p_fecha,
                v_hora_sal, v_hora_llg, v_duracion,
                ROUND(v_precio * 0.9, -2), v_internacional
            );

            SET v_nuevo_vuelo = LAST_INSERT_ID();

            INSERT INTO inventario_asientos (id_vuelo, id_tipo_asiento, asientos_totales, asientos_disponibles) VALUES
                (v_nuevo_vuelo, 1, 150, 150),
                (v_nuevo_vuelo, 2,  30,  30),
                (v_nuevo_vuelo, 3,  10,  10);

        END IF;

        -- Devolver vuelos disponibles para esa ruta y fecha
        SELECT
            v.id_vuelo,
            v.origen,
            v.destino,
            v.fecha_salida,
            v.hora_salida,
            v.hora_llegada,
            v.duracion_min,
            v.precio_base,
            v.vuelo_internacional,
            a2.nombre AS aerolinea,
            SUM(ia.asientos_disponibles) AS total_disponibles
        FROM vuelo v
        JOIN avion av       ON av.id_avion     = v.id_avion
        JOIN aerolinea a2   ON a2.id_aerolinea = av.id_aerolinea
        JOIN inventario_asientos ia ON ia.id_vuelo = v.id_vuelo
        WHERE v.origen       = p_origen
          AND v.destino      = p_destino
          AND v.fecha_salida = p_fecha
        GROUP BY v.id_vuelo
        ORDER BY v.hora_salida;

    END IF;
END$$

-- Confirmar pago y emitir boleto
CREATE PROCEDURE sp_confirmar_pago(
    IN p_id_reservacion INT,
    IN p_monto          DECIMAL(10,2),
    IN p_metodo         VARCHAR(50)
)
BEGIN
    DECLARE v_id_usuario      INT;
    DECLARE v_id_vuelo        INT;
    DECLARE v_id_tipo_asiento INT;
    DECLARE v_precio_base     DECIMAL(10,2);
    DECLARE v_incremento      DECIMAL(5,2);
    DECLARE v_costo_final     DECIMAL(10,2);
    DECLARE v_codigo          VARCHAR(20);

    SELECT id_usuario, id_vuelo, id_tipo_asiento
      INTO v_id_usuario, v_id_vuelo, v_id_tipo_asiento
    FROM reservacion WHERE id_reservacion = p_id_reservacion;

    SELECT precio_base           INTO v_precio_base FROM vuelo       WHERE id_vuelo        = v_id_vuelo;
    SELECT porcentaje_incremento INTO v_incremento  FROM tipo_asiento WHERE id_tipo_asiento = v_id_tipo_asiento;

    SET v_costo_final = v_precio_base * (1 + v_incremento / 100);
    SET v_codigo      = CONCAT('AS-', YEAR(NOW()), '-', LPAD(p_id_reservacion, 6, '0'));

    INSERT INTO pago (id_reservacion, monto, metodo_pago, fecha_pago, aprobado)
    VALUES (p_id_reservacion, p_monto, p_metodo, NOW(), TRUE);

    INSERT INTO boleto (id_usuario, id_vuelo, id_tipo_asiento, id_reservacion, codigo_boleto, costo_base, costo_final)
    VALUES (v_id_usuario, v_id_vuelo, v_id_tipo_asiento, p_id_reservacion, v_codigo, v_precio_base, v_costo_final);

    SELECT v_codigo AS codigo_boleto, v_costo_final AS costo_final;
END$$

-- Cancelar reservación con reembolso automático
CREATE PROCEDURE sp_cancelar_reservacion(
    IN p_id_reservacion INT,
    IN p_id_usuario     INT,
    IN p_motivo         VARCHAR(255)
)
BEGIN
    DECLARE v_estado          VARCHAR(20);
    DECLARE v_id_vuelo        INT;
    DECLARE v_id_tipo_asiento INT;
    DECLARE v_salida          DATETIME;
    DECLARE v_dias_antes      INT;
    DECLARE v_monto_pagado    DECIMAL(10,2);

    SELECT estado, id_vuelo, id_tipo_asiento
      INTO v_estado, v_id_vuelo, v_id_tipo_asiento
    FROM reservacion
    WHERE id_reservacion = p_id_reservacion AND id_usuario = p_id_usuario;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reservacion no encontrada';
    END IF;

    IF v_estado IN ('cancelada','expirada') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Esta reservacion ya no puede cancelarse';
    END IF;

    SELECT dias_antes INTO v_dias_antes
    FROM politica_cancelacion WHERE activo = TRUE LIMIT 1;

    SELECT TIMESTAMP(fecha_salida, hora_salida) INTO v_salida
    FROM vuelo WHERE id_vuelo = v_id_vuelo;

    IF NOW() > DATE_SUB(v_salida, INTERVAL v_dias_antes DAY) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cancelacion fuera del plazo permitido';
    END IF;

    UPDATE reservacion SET estado = 'cancelada' WHERE id_reservacion = p_id_reservacion;

    UPDATE inventario_asientos
    SET asientos_disponibles = asientos_disponibles + 1
    WHERE id_vuelo = v_id_vuelo AND id_tipo_asiento = v_id_tipo_asiento;

    INSERT INTO cancelacion (id_reservacion, motivo)
    VALUES (p_id_reservacion, p_motivo);

    SELECT IFNULL(SUM(monto), 0) INTO v_monto_pagado
    FROM pago
    WHERE id_reservacion = p_id_reservacion
      AND aprobado = TRUE
      AND tipo_movimiento = 'pago';

    IF v_monto_pagado > 0 THEN
        INSERT INTO pago (id_reservacion, monto, metodo_pago, aprobado, tipo_movimiento)
        VALUES (p_id_reservacion, -v_monto_pagado, 'REEMBOLSO', TRUE, 'reembolso');
    END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------------------
-- VISTAS
-- --------------------------------------------------------------------
CREATE VIEW vw_reservaciones_por_mes AS
SELECT DATE_FORMAT(fecha_reserva, '%Y-%m') AS mes, COUNT(*) AS reservaciones
FROM reservacion GROUP BY mes ORDER BY mes;

CREATE VIEW vw_cancelaciones_por_mes AS
SELECT DATE_FORMAT(fecha_cancelacion, '%Y-%m') AS mes, COUNT(*) AS cancelaciones
FROM cancelacion GROUP BY mes ORDER BY mes;

-- --------------------------------------------------------------------
-- DATOS DE PRUEBA
-- --------------------------------------------------------------------
INSERT INTO aerolinea (nombre, codigo, pais_origen) VALUES
('AeroMexico',        'AM', 'Mexico'),
('Volaris',           'Y4', 'Mexico'),
('Viva Aerobus',      'VB', 'Mexico'),
('American Airlines', 'AA', 'Estados Unidos'),
('Copa Airlines',     'CM', 'Panama');

INSERT INTO tipo_avion (modelo, capacidad, fabricante) VALUES
('Boeing 737 MAX', 180, 'Boeing'),
('Airbus A320neo', 186, 'Airbus'),
('Airbus A320',    180, 'Airbus'),
('Boeing 787',     242, 'Boeing');

INSERT INTO avion (id_aerolinea, id_tipo_avion, matricula) VALUES
(1,1,'AMX-001'),(2,2,'VLR-002'),(3,3,'VVB-003'),(4,4,'AAL-004'),(5,2,'COP-005');

INSERT INTO piloto (nombre, licencia, anios_experiencia, id_aerolinea) VALUES
('Carlos Mendoza', 'LIC-1001', 12, 1),
('Ana Torres',     'LIC-1002',  8, 2),
('Luis Ramos',     'LIC-1003', 15, 3),
('John Smith',     'LIC-1004', 20, 4),
('Maria Castillo', 'LIC-1005', 10, 5);

INSERT INTO tipo_asiento (descripcion, porcentaje_incremento, precio_base) VALUES
('Economica',     0.00, 1500.00),
('Business',     50.00, 1500.00),
('Primera Clase',100.00, 1500.00);

INSERT INTO destino (ciudad, pais, codigo_iata, descripcion, imagen_url) VALUES
('Ciudad de Mexico','Mexico', 'MEX','Capital del pais, cultura y gastronomia',      'https://images.unsplash.com/photo-1518105779142-d975f22f1b0a?w=600'),
('Cancun',          'Mexico', 'CUN','Playas del Caribe, turismo y entretenimiento', 'https://images.unsplash.com/photo-1552074284-5e84a3f7c85f?w=600'),
('Guadalajara',     'Mexico', 'GDL','Ciudad del tequila, tecnologia y cultura',     'https://images.unsplash.com/photo-1585464231875-d9ef1f5ad396?w=600'),
('Monterrey',       'Mexico', 'MTY','Ciudad industrial, negocios y turismo',        'https://images.unsplash.com/photo-1601134467661-3d775b999c18?w=600'),
('Los Cabos',       'Mexico', 'SJD','Destino de lujo, playas y naturaleza',         'https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=600'),
('Miami',           'USA',    'MIA','Ciudad costera, negocios y entretenimiento',   'https://images.unsplash.com/photo-1533106497176-45ae19e68ba2?w=600'),
('Nueva York',      'USA',    'JFK','La gran manzana, cultura y finanzas',          'https://images.unsplash.com/photo-1496442226666-8d4d0e62e6e9?w=600'),
('Panama',          'Panama', 'PTY','Hub de conexiones, canal y comercio',          'https://images.unsplash.com/photo-1512813498716-3e640fed3f39?w=600');

-- Verificación final
SELECT 'Base de datos AeroSystem v2 creada correctamente' AS resultado;
SELECT ciudad, pais, codigo_iata FROM destino ORDER BY ciudad;
