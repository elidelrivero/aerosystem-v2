# AeroSystem ✈

Sistema web de reservación de vuelos desarrollado como proyecto universitario. Permite a los usuarios buscar vuelos, hacer reservaciones, procesar pagos y gestionar sus viajes desde una interfaz web moderna.

---

## ¿Qué hace?

El sistema simula una plataforma de aerolínea donde cualquier usuario puede registrarse con su nombre y correo, buscar vuelos entre 8 destinos disponibles, elegir su clase de asiento y completar el proceso de compra. También puede consultar sus boletos y cancelar reservaciones desde su panel personal.

Una de las características más interesantes es que los vuelos se generan dinámicamente: si el usuario busca una ruta que no existe en la base de datos para cierta fecha, el sistema la crea automáticamente con dos opciones de horario (mañana y tarde), lo que hace que cualquier combinación de origen, destino y fecha futura siempre devuelva resultados.

---

## Stack

- **Backend:** Python 3 con Flask
- **Base de datos:** MySQL 8
- **Frontend:** HTML5, CSS3 con variables y Grid, Jinja2
- **Conector:** mysql-connector-python

No se usaron frameworks CSS como Bootstrap. Todo el diseño está hecho a mano con variables CSS y layout con Grid/Flexbox.

---

## Características principales

**Para el usuario:**
- Registro e inicio de sesión solo con nombre y correo, sin contraseña
- Buscador de vuelos con selector de ciudades y fecha
- Wizard de compra en 4 pasos: ruta → vuelo → clase → pago
- Dos opciones de vuelo por ruta (horario mañana y tarde, el de tarde con descuento)
- Panel personal con historial de boletos y reservaciones
- Cancelación de vuelos con reembolso automático si aplica

**En la base de datos:**
- Generación dinámica de vuelos al momento de la búsqueda
- Triggers para control de inventario de asientos y validación de duplicados
- Stored procedures para login (upsert), confirmación de pago y cancelación
- Evento programado que expira reservaciones pendientes cada hora
- Política de cancelación configurable sin tocar código
- Reembolso automático al cancelar si hubo pago previo

---

## Instalación

### Requisitos
- Python 3.9 o superior
- MySQL 8.0 o superior

### Pasos

```bash
# Instalar dependencias
pip install flask mysql-connector-python

# Cargar la base de datos
mysql -u root -p < aerosystem.sql

# Correr la aplicación
python app.py
```

Abrir en el navegador: `http://localhost:5000`

---

## Estructura del proyecto

```
aerosystem_v2/
├── app.py                  # Backend: rutas, lógica y conexión a BD
├── aerosystem.sql          # Schema completo + datos de prueba
├── .gitignore
└── templates/
    ├── base.html           # Layout base con navbar y estilos globales
    ├── index.html          # Landing page con buscador y destinos
    ├── login.html          # Registro e inicio de sesión
    ├── buscar.html         # Paso 1: selección de ruta y fecha
    ├── vuelos.html         # Paso 2: lista de vuelos disponibles
    ├── asiento.html        # Paso 3: elección de clase
    ├── pagar.html          # Paso 4: resumen y confirmación de pago
    ├── mis_viajes.html     # Panel personal del usuario
    └── cancelar.html       # Confirmación de cancelación
```

---

## Flujo de uso

```
Inicio → Login → Buscar vuelo → Elegir vuelo → Elegir clase → Pagar → Mis viajes
                                                                           ↓
                                                                       Cancelar
```

---

## Destinos disponibles

| Ciudad | País | IATA |
|--------|------|------|
| Ciudad de Mexico | Mexico | MEX |
| Cancun | Mexico | CUN |
| Guadalajara | Mexico | GDL |
| Monterrey | Mexico | MTY |
| Los Cabos | Mexico | SJD |
| Miami | USA | MIA |
| Nueva York | USA | JFK |
| Panama | Panama | PTY |

---

## Modelo de datos

```
usuario ──< reservacion >── vuelo ──< inventario_asientos >── tipo_asiento
                               └──< destino (origen/destino)
reservacion ──< boleto
reservacion ──< pago
reservacion ──< cancelacion
vuelo >── avion >── aerolinea
vuelo >── piloto
```

---

## Notas técnicas

**Vuelos dinámicos:** La lógica de generación de vuelos vive en Python (`app.py`, ruta `/vuelos`) en lugar de un stored procedure, por compatibilidad con `mysql-connector-python` que tiene limitaciones al manejar resultados de procedures que también hacen escrituras.

**Sesiones:** Se usa `flask.session` con una `secret_key` para mantener al usuario autenticado entre requests. El decorador `@login_required` protege todas las rutas que lo requieren.

**Formato de tiempo:** MySQL devuelve campos `TIME` como objetos `timedelta` de Python. Se registró un filtro personalizado en Jinja2 (`fmt_time`) para convertirlos a formato `HH:MM` legible en los templates.

---

## Autor

Edgar — Estudiante de Ingeniería en Sistemas Computacionales
