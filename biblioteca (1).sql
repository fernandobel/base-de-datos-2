-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Servidor: 127.0.0.1
-- Tiempo de generación: 29-06-2025 a las 22:56:38
-- Versión del servidor: 10.4.32-MariaDB
-- Versión de PHP: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de datos: `biblioteca`
--

DELIMITER $$
--
-- Procedimientos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `aplicar_sancion_manual` (IN `p_id_estudiante` INT, IN `p_id_bibliotecario` INT, IN `p_tipo` VARCHAR(50), IN `p_descripcion` TEXT, IN `p_monto` DECIMAL(10,2), IN `p_id_prestamo` INT)   BEGIN
    DECLARE v_sanciones_activas INT;
    IF NOT EXISTS (SELECT 1 FROM bibliotecarios WHERE id_bibliotecario = p_id_bibliotecario) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El bibliotecario no existe o no tiene permisos para aplicar sanciones.';
    END IF;
    INSERT INTO sanciones (id_estudiante, id_prestamo, id_bibliotecario, tipo, descripcion, monto, fecha_sancion, estado)
    VALUES (p_id_estudiante, p_id_prestamo, p_id_bibliotecario, p_tipo, p_descripcion, p_monto, CURDATE(), 'activa');
    SELECT COUNT(*) INTO v_sanciones_activas
    FROM sanciones
    WHERE id_estudiante = p_id_estudiante 
    AND fecha_sancion >= DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 6 MONTH)
    AND estado = 'activa';    
    IF v_sanciones_activas > 3 THEN
        UPDATE estudiantes SET estado = 'suspendido' WHERE id_estudiante = p_id_estudiante;
    END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `registrar_devolucion` (IN `p_id_prestamo` INT, IN `p_id_bibliotecario` INT, IN `p_observaciones` TEXT)   BEGIN
    DECLARE v_fecha_estimada DATE;    
    DECLARE v_dias_retraso INT;        
    DECLARE v_multa DECIMAL(10,2);    
    DECLARE v_id_ejemplar INT;       
    DECLARE v_id_estudiante INT;       
    SELECT fecha_devolucion_estimada, id_ejemplar, id_estudiante 
    INTO v_fecha_estimada, v_id_ejemplar, v_id_estudiante
    FROM prestamos 
    WHERE id_prestamo = p_id_prestamo;
    SET v_dias_retraso = GREATEST(0, DATEDIFF(CURDATE(), v_fecha_estimada));
    
    IF v_dias_retraso > 0 THEN
        SET v_multa = v_dias_retraso * 5.00; 
        INSERT INTO sanciones (id_estudiante, id_prestamo, id_bibliotecario, tipo, descripcion, monto, fecha_sancion, estado)
        VALUES (v_id_estudiante, p_id_prestamo, p_id_bibliotecario, 'retraso', 
                CONCAT('Retraso en devolución: ', v_dias_retraso, ' días'), v_multa, CURDATE(), 'activa');
    ELSE
        SET v_multa = 0;
    END IF;
    INSERT INTO devoluciones (id_prestamo, id_bibliotecario, fecha_devolucion, multa_aplicada, observaciones)
    VALUES (p_id_prestamo, p_id_bibliotecario, NOW(), v_multa, p_observaciones);
    UPDATE prestamos SET estado = 'devuelto' WHERE id_prestamo = p_id_prestamo;
    UPDATE ejemplares SET estado = 'disponible' WHERE id_ejemplar = v_id_ejemplar;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `registrar_prestamo` (IN `p_id_estudiante` INT, IN `p_id_ejemplar` INT, IN `p_id_bibliotecario` INT)   BEGIN
    DECLARE v_prestamos_activos INT;      
    DECLARE v_estado_estudiante VARCHAR(20);
    DECLARE v_estado_ejemplar VARCHAR(20); 
    DECLARE v_fecha_devolucion DATE;   
    SELECT estado INTO v_estado_estudiante FROM estudiantes WHERE id_estudiante = p_id_estudiante;
    IF v_estado_estudiante = 'suspendido' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El estudiante está suspendido y no puede realizar préstamos';
    END IF;
    SELECT COUNT(*) INTO v_prestamos_activos 
    FROM prestamos 
    WHERE id_estudiante = p_id_estudiante AND estado = 'activo';
    
    IF v_prestamos_activos >= 3 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El estudiante ya tiene 3 préstamos activos, no puede tomar más';
    END IF;
    SELECT estado INTO v_estado_ejemplar FROM ejemplares WHERE id_ejemplar = p_id_ejemplar;
    IF v_estado_ejemplar != 'disponible' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El ejemplar no está disponible para préstamo';
    END IF;
    SET v_fecha_devolucion = DATE_ADD(CURDATE(), INTERVAL 15 DAY);
    INSERT INTO prestamos (id_estudiante, id_ejemplar, id_bibliotecario, fecha_prestamo, fecha_devolucion_estimada, estado)
    VALUES (p_id_estudiante, p_id_ejemplar, p_id_bibliotecario, NOW(), v_fecha_devolucion, 'activo');
    UPDATE ejemplares SET estado = 'prestado' WHERE id_ejemplar = p_id_ejemplar;
END$$

--
-- Funciones
--
CREATE DEFINER=`root`@`localhost` FUNCTION `calcular_multa` (`p_fecha_devolucion_estimada` DATE, `p_fecha_devolucion_real` DATE) RETURNS DECIMAL(10,2) DETERMINISTIC BEGIN
    DECLARE v_dias_retraso INT; 
    DECLARE v_multa DECIMAL(10,2); 
    SET v_dias_retraso = GREATEST(0, DATEDIFF(p_fecha_devolucion_real, p_fecha_devolucion_estimada));
    SET v_multa = v_dias_retraso * 5.00;  
    RETURN v_multa;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `total_prestamos_por_estudiante` (`p_id_estudiante` INT, `p_periodo_meses` INT) RETURNS INT(11) DETERMINISTIC BEGIN
    DECLARE v_total INT; 
    IF p_periodo_meses IS NULL THEN
        SELECT COUNT(*) INTO v_total
        FROM prestamos
        WHERE id_estudiante = p_id_estudiante;
    ELSE
        SELECT COUNT(*) INTO v_total
        FROM prestamos
        WHERE id_estudiante = p_id_estudiante
        AND fecha_prestamo >= DATE_SUB(CURDATE(), INTERVAL p_periodo_meses MONTH);
    END IF;
    
    RETURN v_total;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `administradores`
--

CREATE TABLE `administradores` (
  `id_administrador` bigint(20) UNSIGNED NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `apellido` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `nivel_acceso` int(11) DEFAULT 3 CHECK (`nivel_acceso` = 3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `administradores`
--

INSERT INTO `administradores` (`id_administrador`, `nombre`, `apellido`, `email`, `telefono`, `nivel_acceso`) VALUES
(2, 'luisa', 'schumaher', 'verstapen@warhammer.com', '041498080', 3),
(3, 'oscar', 'salina', 'salina@warhammer.com', '12345', 3);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `areas_academicas`
--

CREATE TABLE `areas_academicas` (
  `id_area` bigint(20) UNSIGNED NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `descripcion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `areas_academicas`
--

INSERT INTO `areas_academicas` (`id_area`, `nombre`, `descripcion`) VALUES
(1, '\r\n        Computación', 'Libros relacionados con programación, desarrollo de software, etc.'),
(2, 'literatura\r\n', 'Libros relacionados con accion, mundos alternativos,historia geografica, etc.'),
(3, 'psicologia', 'ciencias de la persepcion cognitiva, logica y pensamiento critico');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `bibliotecarios`
--

CREATE TABLE `bibliotecarios` (
  `id_bibliotecario` bigint(20) UNSIGNED NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `apellido` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `nivel_acceso` int(11) DEFAULT 1 CHECK (`nivel_acceso` between 1 and 2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `bibliotecarios`
--

INSERT INTO `bibliotecarios` (`id_bibliotecario`, `nombre`, `apellido`, `email`, `telefono`, `nivel_acceso`) VALUES
(1, 'Carlos', 'López', 'carloslopez@biblioteca.com', '0987654321', 2),
(2, 'carmen', 'alejandra', 'carale@biblioteca.com', '1222243567', 1),
(3, 'jhoe', 'schumaher', 'max@biblioteca.com', '04345567465', 2);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `devoluciones`
--

CREATE TABLE `devoluciones` (
  `id_devolucion` bigint(20) UNSIGNED NOT NULL,
  `id_prestamo` int(11) NOT NULL,
  `fecha_devolucion` timestamp NOT NULL DEFAULT current_timestamp(),
  `id_bibliotecario` int(11) DEFAULT NULL,
  `multa_aplicada` decimal(10,2) DEFAULT 0.00,
  `observaciones` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `devoluciones`
--

INSERT INTO `devoluciones` (`id_devolucion`, `id_prestamo`, `fecha_devolucion`, `id_bibliotecario`, `multa_aplicada`, `observaciones`) VALUES
(1, 1, '2025-06-29 20:23:56', 1, 5.00, 'Devolución tardía de 1 día.');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `ejemplares`
--

CREATE TABLE `ejemplares` (
  `id_ejemplar` bigint(20) UNSIGNED NOT NULL,
  `id_libro` int(11) NOT NULL,
  `codigo_barras` varchar(50) NOT NULL,
  `estado` varchar(20) DEFAULT 'disponible' CHECK (`estado` in ('disponible','prestado','reparacion','perdido')),
  `ubicacion` varchar(100) NOT NULL,
  `fecha_adquisicion` date DEFAULT curdate()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `ejemplares`
--

INSERT INTO `ejemplares` (`id_ejemplar`, `id_libro`, `codigo_barras`, `estado`, `ubicacion`, `fecha_adquisicion`) VALUES
(1, 1, 'abcds45638127', 'disponible', 'Estantería A1', '2025-06-29');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `estudiantes`
--

CREATE TABLE `estudiantes` (
  `id_estudiante` bigint(20) UNSIGNED NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `apellido` varchar(100) NOT NULL,
  `email` varchar(100) NOT NULL,
  `telefono` varchar(20) DEFAULT NULL,
  `estado` varchar(20) DEFAULT 'activo' CHECK (`estado` in ('activo','suspendido')),
  `fecha_registro` date DEFAULT curdate()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `estudiantes`
--

INSERT INTO `estudiantes` (`id_estudiante`, `nombre`, `apellido`, `email`, `telefono`, `estado`, `fecha_registro`) VALUES
(1, 'Pérez', 'jimenez', 'perez@estudiante.com', '555112233', 'activo', '2025-06-29'),
(2, 'Andrea', 'Contreras', 'andrea.contreras@estudiante.com', '555998877', 'activo', '2024-01-15'),
(3, 'Roberto', 'González', 'roberto.gonzalez@estudiante.com', '555443322', 'suspendido', '2024-03-10');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `libros`
--

CREATE TABLE `libros` (
  `id_libro` bigint(20) UNSIGNED NOT NULL,
  `titulo` varchar(200) NOT NULL,
  `autor` varchar(200) NOT NULL,
  `isbn` varchar(20) DEFAULT NULL,
  `anio_publicacion` int(11) DEFAULT NULL,
  `editorial` varchar(100) DEFAULT NULL,
  `id_area` int(11) DEFAULT NULL,
  `disponible_digital` tinyint(1) DEFAULT 0,
  `url_digital` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `libros`
--

INSERT INTO `libros` (`id_libro`, `titulo`, `autor`, `isbn`, `anio_publicacion`, `editorial`, `id_area`, `disponible_digital`, `url_digital`) VALUES
(1, 'Introducción a SQL', 'Claudio Data', '978-84-123456-7-8', 2023, 'Editorial Tech', 1, 0, NULL),
(2, 'Literatura Fantástica Moderna', 'Elsa Imaginativa', '978-84-987654-3-2', 2021, 'Letras Oscuras', 2, 1, 'https://ejemplo.com/literatura_fantastica.pdf'),
(3, 'Psicología del Aprendizaje', 'Dr. Mente Clara', '978-84-000000-0-0', 2019, 'Conocimiento Ediciones', 3, 0, NULL),
(4, 'Desarrollo Web con Python', 'Código Abierto', '978-1-234567-89-0', 2022, 'Programación Fácil', 1, 1, 'https://ejemplo.com/web_python.pdf');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `libros_temas`
--

CREATE TABLE `libros_temas` (
  `id_libro` int(11) NOT NULL,
  `id_tema` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `libros_temas`
--

INSERT INTO `libros_temas` (`id_libro`, `id_tema`) VALUES
(1, 1),
(2, 2),
(3, 3),
(4, 1);

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `log_acciones`
--

CREATE TABLE `log_acciones` (
  `id_log` bigint(20) UNSIGNED NOT NULL,
  `tabla_afectada` varchar(50) NOT NULL,
  `id_registro_afectado` int(11) DEFAULT NULL,
  `tipo_accion` varchar(20) NOT NULL CHECK (`tipo_accion` in ('INSERT','UPDATE','DELETE')),
  `usuario_responsable` varchar(100) NOT NULL,
  `fecha_accion` timestamp NOT NULL DEFAULT current_timestamp(),
  `datos_anteriores` text DEFAULT NULL,
  `datos_nuevos` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `log_acciones`
--

INSERT INTO `log_acciones` (`id_log`, `tabla_afectada`, `id_registro_afectado`, `tipo_accion`, `usuario_responsable`, `fecha_accion`, `datos_anteriores`, `datos_nuevos`) VALUES
(1, 'estudiantes', 1, 'UPDATE', 'admin@localhost', '2025-06-29 20:36:02', NULL, 'Estado del estudiante cambiado a activo'),
(2, 'prestamos', 101, 'INSERT', 'bibliotecario@localhost', '2025-06-29 20:36:02', NULL, 'Nuevo préstamo de libro ID 4 a estudiante ID 1');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `prestamos`
--

CREATE TABLE `prestamos` (
  `id_prestamo` bigint(20) UNSIGNED NOT NULL,
  `id_estudiante` int(11) NOT NULL,
  `id_ejemplar` int(11) NOT NULL,
  `id_bibliotecario` int(11) DEFAULT NULL,
  `fecha_prestamo` timestamp NOT NULL DEFAULT current_timestamp(),
  `fecha_devolucion_estimada` date NOT NULL,
  `estado` varchar(20) DEFAULT 'activo' CHECK (`estado` in ('activo','devuelto','vencido'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `prestamos`
--

INSERT INTO `prestamos` (`id_prestamo`, `id_estudiante`, `id_ejemplar`, `id_bibliotecario`, `fecha_prestamo`, `fecha_devolucion_estimada`, `estado`) VALUES
(1, 1, 1, 1, '2025-06-29 20:37:58', '2025-07-14', 'activo'),
(2, 1, 1, 2, '2025-06-20 04:00:00', '2025-07-05', 'devuelto');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `sanciones`
--

CREATE TABLE `sanciones` (
  `id_sancion` bigint(20) UNSIGNED NOT NULL,
  `id_estudiante` int(11) NOT NULL,
  `id_prestamo` int(11) DEFAULT NULL,
  `id_bibliotecario` int(11) DEFAULT NULL,
  `fecha_sancion` date DEFAULT curdate(),
  `tipo` varchar(50) NOT NULL CHECK (`tipo` in ('retraso','daño','perdida','otra')),
  `descripcion` text NOT NULL,
  `monto` decimal(10,2) DEFAULT 0.00,
  `estado` varchar(20) DEFAULT 'activa' CHECK (`estado` in ('activa','pagada','perdonada'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `sanciones`
--

INSERT INTO `sanciones` (`id_sancion`, `id_estudiante`, `id_prestamo`, `id_bibliotecario`, `fecha_sancion`, `tipo`, `descripcion`, `monto`, `estado`) VALUES
(1, 1, NULL, 1, '2025-06-29', 'daño', 'Página dañada en el libro.', 10.00, 'activa'),
(2, 1, 1, 1, '2025-06-25', 'retraso', 'Devolución 3 días tarde del libro de SQL.', 15.00, 'pagada');

-- --------------------------------------------------------

--
-- Estructura de tabla para la tabla `temas`
--

CREATE TABLE `temas` (
  `id_tema` bigint(20) UNSIGNED NOT NULL,
  `nombre` varchar(100) NOT NULL,
  `descripcion` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Volcado de datos para la tabla `temas`
--

INSERT INTO `temas` (`id_tema`, `nombre`, `descripcion`) VALUES
(1, 'Bases de Datos', 'Temas relacionados con diseño y gestión de bases de datos.'),
(2, 'Ficción', 'Géneros literarios de fantasía, ciencia ficción, aventura.'),
(3, 'Desarrollo Web', 'Tecnologías y lenguajes para la creación de sitios web.');

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_estadisticas_mensuales`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_estadisticas_mensuales` (
`mes` varchar(10)
,`total_prestamos` bigint(21)
,`total_devoluciones` bigint(21)
,`devoluciones_con_multa` decimal(22,0)
,`total_multas` decimal(32,2)
,`total_sanciones` bigint(21)
,`estudiantes_activos` bigint(21)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_libros_disponibles`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_libros_disponibles` (
`id_libro` bigint(20) unsigned
,`titulo` varchar(200)
,`autor` varchar(200)
,`area_academica` varchar(100)
,`temas` mediumtext
,`ejemplares_disponibles` decimal(22,0)
,`disponible_digital` tinyint(1)
);

-- --------------------------------------------------------

--
-- Estructura Stand-in para la vista `vista_prestamos_estudiante`
-- (Véase abajo para la vista actual)
--
CREATE TABLE `vista_prestamos_estudiante` (
`id_estudiante` bigint(20) unsigned
,`estudiante` varchar(201)
,`id_prestamo` bigint(20) unsigned
,`titulo` varchar(200)
,`codigo_barras` varchar(50)
,`fecha_prestamo` timestamp
,`fecha_devolucion_estimada` date
,`estado_prestamo` varchar(8)
,`multa` decimal(10,2)
);

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_estadisticas_mensuales`
--
DROP TABLE IF EXISTS `vista_estadisticas_mensuales`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_estadisticas_mensuales`  AS SELECT date_format(`p`.`fecha_prestamo`,'%Y-%m-01') AS `mes`, count(`p`.`id_prestamo`) AS `total_prestamos`, count(`d`.`id_devolucion`) AS `total_devoluciones`, sum(case when `d`.`multa_aplicada` > 0 then 1 else 0 end) AS `devoluciones_con_multa`, sum(ifnull(`d`.`multa_aplicada`,0)) AS `total_multas`, count(`s`.`id_sancion`) AS `total_sanciones`, count(distinct `p`.`id_estudiante`) AS `estudiantes_activos` FROM ((`prestamos` `p` left join `devoluciones` `d` on(`p`.`id_prestamo` = `d`.`id_prestamo`)) left join `sanciones` `s` on(`p`.`id_estudiante` = `s`.`id_estudiante` and date_format(`s`.`fecha_sancion`,'%Y-%m-01') = date_format(`p`.`fecha_prestamo`,'%Y-%m-01'))) GROUP BY date_format(`p`.`fecha_prestamo`,'%Y-%m-01') ORDER BY date_format(`p`.`fecha_prestamo`,'%Y-%m-01') DESC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_libros_disponibles`
--
DROP TABLE IF EXISTS `vista_libros_disponibles`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_libros_disponibles`  AS SELECT `l`.`id_libro` AS `id_libro`, `l`.`titulo` AS `titulo`, `l`.`autor` AS `autor`, `a`.`nombre` AS `area_academica`, group_concat(`t`.`nombre` separator ', ') AS `temas`, sum(case when `ej`.`estado` = 'disponible' then 1 else 0 end) AS `ejemplares_disponibles`, `l`.`disponible_digital` AS `disponible_digital` FROM ((((`libros` `l` join `areas_academicas` `a` on(`l`.`id_area` = `a`.`id_area`)) left join `libros_temas` `lt` on(`l`.`id_libro` = `lt`.`id_libro`)) left join `temas` `t` on(`lt`.`id_tema` = `t`.`id_tema`)) left join `ejemplares` `ej` on(`l`.`id_libro` = `ej`.`id_libro`)) GROUP BY `l`.`id_libro`, `a`.`nombre`, `l`.`disponible_digital` HAVING sum(case when `ej`.`estado` = 'disponible' then 1 else 0 end) > 0 OR `l`.`disponible_digital` = 1 ORDER BY `l`.`titulo` ASC ;

-- --------------------------------------------------------

--
-- Estructura para la vista `vista_prestamos_estudiante`
--
DROP TABLE IF EXISTS `vista_prestamos_estudiante`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `vista_prestamos_estudiante`  AS SELECT `e`.`id_estudiante` AS `id_estudiante`, concat(`e`.`nombre`,' ',`e`.`apellido`) AS `estudiante`, `p`.`id_prestamo` AS `id_prestamo`, `l`.`titulo` AS `titulo`, `ej`.`codigo_barras` AS `codigo_barras`, `p`.`fecha_prestamo` AS `fecha_prestamo`, `p`.`fecha_devolucion_estimada` AS `fecha_devolucion_estimada`, CASE WHEN `p`.`estado` = 'devuelto' THEN 'Devuelto' WHEN curdate() > `p`.`fecha_devolucion_estimada` THEN 'Vencido' ELSE 'Activo' END AS `estado_prestamo`, ifnull(`d`.`multa_aplicada`,0) AS `multa` FROM ((((`estudiantes` `e` join `prestamos` `p` on(`e`.`id_estudiante` = `p`.`id_estudiante`)) join `ejemplares` `ej` on(`p`.`id_ejemplar` = `ej`.`id_ejemplar`)) join `libros` `l` on(`ej`.`id_libro` = `l`.`id_libro`)) left join `devoluciones` `d` on(`p`.`id_prestamo` = `d`.`id_prestamo`)) ORDER BY `e`.`id_estudiante` ASC, `p`.`fecha_prestamo` DESC ;

--
-- Índices para tablas volcadas
--

--
-- Indices de la tabla `administradores`
--
ALTER TABLE `administradores`
  ADD PRIMARY KEY (`id_administrador`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indices de la tabla `areas_academicas`
--
ALTER TABLE `areas_academicas`
  ADD PRIMARY KEY (`id_area`),
  ADD UNIQUE KEY `nombre` (`nombre`);

--
-- Indices de la tabla `bibliotecarios`
--
ALTER TABLE `bibliotecarios`
  ADD PRIMARY KEY (`id_bibliotecario`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indices de la tabla `devoluciones`
--
ALTER TABLE `devoluciones`
  ADD PRIMARY KEY (`id_devolucion`),
  ADD UNIQUE KEY `id_prestamo` (`id_prestamo`);

--
-- Indices de la tabla `ejemplares`
--
ALTER TABLE `ejemplares`
  ADD PRIMARY KEY (`id_ejemplar`),
  ADD UNIQUE KEY `codigo_barras` (`codigo_barras`);

--
-- Indices de la tabla `estudiantes`
--
ALTER TABLE `estudiantes`
  ADD PRIMARY KEY (`id_estudiante`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indices de la tabla `libros`
--
ALTER TABLE `libros`
  ADD PRIMARY KEY (`id_libro`),
  ADD UNIQUE KEY `isbn` (`isbn`);

--
-- Indices de la tabla `libros_temas`
--
ALTER TABLE `libros_temas`
  ADD PRIMARY KEY (`id_libro`,`id_tema`);

--
-- Indices de la tabla `log_acciones`
--
ALTER TABLE `log_acciones`
  ADD PRIMARY KEY (`id_log`);

--
-- Indices de la tabla `prestamos`
--
ALTER TABLE `prestamos`
  ADD PRIMARY KEY (`id_prestamo`);

--
-- Indices de la tabla `sanciones`
--
ALTER TABLE `sanciones`
  ADD PRIMARY KEY (`id_sancion`);

--
-- Indices de la tabla `temas`
--
ALTER TABLE `temas`
  ADD PRIMARY KEY (`id_tema`),
  ADD UNIQUE KEY `nombre` (`nombre`);

--
-- AUTO_INCREMENT de las tablas volcadas
--

--
-- AUTO_INCREMENT de la tabla `administradores`
--
ALTER TABLE `administradores`
  MODIFY `id_administrador` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `areas_academicas`
--
ALTER TABLE `areas_academicas`
  MODIFY `id_area` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `bibliotecarios`
--
ALTER TABLE `bibliotecarios`
  MODIFY `id_bibliotecario` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `devoluciones`
--
ALTER TABLE `devoluciones`
  MODIFY `id_devolucion` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `ejemplares`
--
ALTER TABLE `ejemplares`
  MODIFY `id_ejemplar` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de la tabla `estudiantes`
--
ALTER TABLE `estudiantes`
  MODIFY `id_estudiante` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT de la tabla `libros`
--
ALTER TABLE `libros`
  MODIFY `id_libro` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT de la tabla `log_acciones`
--
ALTER TABLE `log_acciones`
  MODIFY `id_log` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `prestamos`
--
ALTER TABLE `prestamos`
  MODIFY `id_prestamo` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `sanciones`
--
ALTER TABLE `sanciones`
  MODIFY `id_sancion` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de la tabla `temas`
--
ALTER TABLE `temas`
  MODIFY `id_tema` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
