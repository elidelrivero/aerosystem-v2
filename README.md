# ✈ AeroSystem v2

Aplicación web de reservación de vuelos orientada al usuario final, desarrollada con Python/Flask y MySQL.

## Demo del flujo
1. El usuario ingresa su nombre y correo → se crea su cuenta automáticamente
2. Busca vuelos por origen, destino y fecha
3. Elige el vuelo y la clase de asiento (Económica, Business, Primera Clase)
4. Confirma el pago → se emite su boleto con código único
5. Consulta sus viajes, descarga boletos o cancela reservaciones

## Stack tecnológico
| Capa | Tecnología |
|------|-----------|
| Backend | Python 3 · Flask |
| Base de datos | MySQL 8 |
| Frontend | HTML5 · Jinja2 · CSS3 custom (sin frameworks) |
| Sesiones | Flask session (server-side) |

## Características
- Login sin contraseña (nombre + correo) — crea cuenta si no existe
- Wizard de compra en 4 pasos
- Stored procedures para login, búsqueda, pago y cancelación
- Triggers para validación de duplicados e inventario de asientos
- Evento MySQL para expirar reservaciones cada hora
- Reembolso automático al cancelar si hubo pago previo
- Política de cancelación configurable en base de datos

## Instalación

### Requisitos
- Python 3.9+
- MySQL 8.0+

### Pasos
```bash
# 1. Instalar dependencias
pip install flask mysql-connector-python

# 2. Cargar la base de datos
mysql -u root -p < aerosystem.sql

# 3. Correr la app
python app.py
```

Abrir en el navegador: `http://localhost:5000`

## Estructura
```
aerosystem_v2/
├── app.py
├── aerosystem.sql
├── README.md
└── templates/
    ├── base.html
    ├── index.html
    ├── login.html
    ├── buscar.html
    ├── vuelos.html
    ├── asiento.html
    ├── pagar.html
    ├── mis_viajes.html
    └── cancelar.html
```

## Modelo de datos
```
usuario ──< reservacion >── vuelo >── inventario_asientos >── tipo_asiento
reservacion ──< boleto
reservacion ──< pago
reservacion ──< cancelacion
vuelo >── destino (origen/destino)
```
