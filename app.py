import os
from flask import Flask, render_template, request, redirect, url_for, flash, session
import mysql.connector
from mysql.connector import Error as MySQLError

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "aerosystem-secret-2024")

# Filtro para formatear timedelta de MySQL a HH:MM
@app.template_filter('fmt_time')
def fmt_time(td):
    if td is None:
        return ""
    if hasattr(td, 'total_seconds'):
        total = int(td.total_seconds())
        h, m = divmod(total // 60, 60)
        return f"{h:02d}:{m:02d}"
    return str(td)[:5]

DB_CONFIG = {
    "host":     os.environ.get("DB_HOST",     "localhost"),
    "user":     os.environ.get("DB_USER",     "root"),
    "password": os.environ.get("DB_PASSWORD", "root"),
    "database": os.environ.get("DB_NAME",     "aerosystemDB"),
}

def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def login_required(f):
    """Decorador simple: redirige al login si no hay sesión activa."""
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if "id_usuario" not in session:
            flash("Inicia sesión para continuar.", "info")
            return redirect(url_for("login"))
        return f(*args, **kwargs)
    return decorated


# ─────────────────────────────────────────────
#  LANDING / HOME
# ─────────────────────────────────────────────
@app.route("/")
def index():
    conn   = get_db()
    cur    = conn.cursor(dictionary=True)
    cur.execute("SELECT * FROM destino ORDER BY RAND() LIMIT 6")
    destinos = cur.fetchall()
    cur.close(); conn.close()
    return render_template("index.html", destinos=destinos)


# ─────────────────────────────────────────────
#  LOGIN / LOGOUT
# ─────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    if "id_usuario" in session:
        return redirect(url_for("index"))

    if request.method == "POST":
        nombre = request.form["nombre"].strip()
        correo = request.form["correo"].strip().lower()

        if not nombre or not correo:
            flash("Por favor completa todos los campos.", "danger")
            return redirect(url_for("login"))

        try:
            conn = get_db()
            cur  = conn.cursor(dictionary=True)
            cur.callproc("sp_login_usuario", (nombre, correo))
            for result in cur.stored_results():
                usuario = result.fetchone()

            session["id_usuario"] = usuario["id_usuario"]
            session["nombre"]     = usuario["nombre"]
            session["correo"]     = usuario["correo"]
            cur.close(); conn.close()

            flash(f"¡Bienvenido, {usuario['nombre']}!", "success")
            # Si venía de alguna página, regresar ahí
            next_url = request.args.get("next") or url_for("index")
            return redirect(next_url)

        except MySQLError as e:
            flash(f"Error al iniciar sesión: {e.msg}", "danger")

    return render_template("login.html")


@app.route("/logout")
def logout():
    session.clear()
    flash("Has cerrado sesión.", "info")
    return redirect(url_for("index"))


# ─────────────────────────────────────────────
#  WIZARD PASO 1 — BUSCAR VUELO
# ─────────────────────────────────────────────
@app.route("/buscar", methods=["GET", "POST"])
@login_required
def buscar():
    conn = get_db()
    cur  = conn.cursor(dictionary=True)
    cur.execute("SELECT DISTINCT ciudad FROM destino ORDER BY ciudad")
    ciudades = [r["ciudad"] for r in cur.fetchall()]
    cur.close(); conn.close()

    if request.method == "POST":
        origen  = request.form["origen"]
        destino = request.form["destino"]
        fecha   = request.form["fecha"]

        if origen == destino:
            flash("El origen y destino no pueden ser iguales.", "danger")
            return redirect(url_for("buscar"))

        return redirect(url_for("vuelos",
                                origen=origen,
                                destino=destino,
                                fecha=fecha))

    return render_template("buscar.html", ciudades=ciudades)


# ─────────────────────────────────────────────
#  WIZARD PASO 2 — LISTA DE VUELOS
# ─────────────────────────────────────────────
@app.route("/vuelos")
@login_required
def vuelos():
    origen  = request.args.get("origen")
    destino = request.args.get("destino")
    fecha   = request.args.get("fecha")

    if not all([origen, destino, fecha]):
        return redirect(url_for("buscar"))

    from datetime import date
    try:
        fecha_obj = date.fromisoformat(fecha)
    except ValueError:
        flash("Fecha inválida.", "danger")
        return redirect(url_for("buscar"))

    if fecha_obj <= date.today():
        flash("La fecha debe ser a partir de mañana.", "danger")
        return redirect(url_for("buscar"))

    conn = get_db()
    cur  = conn.cursor(dictionary=True)

    # Verificar que ambas ciudades existen en la BD
    cur.execute("SELECT id_destino FROM destino WHERE ciudad = %s", (origen,))
    id_origen = cur.fetchone()
    cur.execute("SELECT id_destino, pais FROM destino WHERE ciudad = %s", (destino,))
    row_destino = cur.fetchone()

    if not id_origen or not row_destino:
        flash("Ciudad no encontrada.", "danger")
        cur.close(); conn.close()
        return redirect(url_for("buscar"))

    # Si no existen vuelos para esa ruta y fecha, crearlos
    cur.execute("""
        SELECT COUNT(*) AS total FROM vuelo
        WHERE origen = %s AND destino = %s AND fecha_salida = %s
    """, (origen, destino, fecha))

    if cur.fetchone()["total"] == 0:
        import random

        # Obtener avión y piloto al azar
        cur.execute("SELECT id_avion FROM avion ORDER BY RAND() LIMIT 1")
        id_avion = cur.fetchone()["id_avion"]
        cur.execute("SELECT id_piloto FROM piloto ORDER BY RAND() LIMIT 1")
        id_piloto = cur.fetchone()["id_piloto"]

        # Determinar si es internacional
        cur.execute("SELECT pais FROM destino WHERE ciudad = %s", (origen,))
        pais_origen = cur.fetchone()["pais"]
        cur.execute("SELECT pais, id_destino FROM destino WHERE ciudad = %s", (destino,))
        row_dest = cur.fetchone()
        pais_destino = row_dest["pais"]
        id_destino   = row_dest["id_destino"]
        cur.execute("SELECT id_destino FROM destino WHERE ciudad = %s", (origen,))
        id_orig = cur.fetchone()["id_destino"]

        es_internacional = pais_origen != pais_destino

        if es_internacional:
            precio   = round(random.randint(3000, 7000) / 100) * 100
            duracion = random.randint(180, 480)
        else:
            precio   = round(random.randint(800, 2300) / 100) * 100
            duracion = random.randint(45, 165)

        from datetime import timedelta, time
        def sumar_hora(hora_base, minutos):
            dt = timedelta(hours=hora_base.hour, minutes=hora_base.minute + minutos)
            total = int(dt.total_seconds())
            h, rem = divmod(total, 3600)
            m = rem // 60
            return time(h % 24, m)

        # Vuelo de mañana 07:00
        h_sal_m = time(7, 0)
        h_llg_m = sumar_hora(h_sal_m, duracion)

        cur.execute("""
            INSERT INTO vuelo (id_avion, id_piloto, id_origen, id_destino,
                origen, destino, fecha_salida, hora_salida, hora_llegada,
                duracion_min, precio_base, vuelo_internacional)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """, (id_avion, id_piloto, id_orig, id_destino,
              origen, destino, fecha,
              h_sal_m, h_llg_m, duracion, precio, es_internacional))
        conn.commit()
        id_vuelo_m = cur.lastrowid

        cur.execute("""
            INSERT INTO inventario_asientos (id_vuelo, id_tipo_asiento, asientos_totales, asientos_disponibles)
            VALUES (%s,1,150,150),(%s,2,30,30),(%s,3,10,10)
        """, (id_vuelo_m, id_vuelo_m, id_vuelo_m))
        conn.commit()

        # Vuelo de tarde 15:00 — 10% más barato
        h_sal_t = time(15, 0)
        h_llg_t = sumar_hora(h_sal_t, duracion)
        precio_tarde = round(precio * 0.9 / 100) * 100

        cur.execute("""
            INSERT INTO vuelo (id_avion, id_piloto, id_origen, id_destino,
                origen, destino, fecha_salida, hora_salida, hora_llegada,
                duracion_min, precio_base, vuelo_internacional)
            VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
        """, (id_avion, id_piloto, id_orig, id_destino,
              origen, destino, fecha,
              h_sal_t, h_llg_t, duracion, precio_tarde, es_internacional))
        conn.commit()
        id_vuelo_t = cur.lastrowid

        cur.execute("""
            INSERT INTO inventario_asientos (id_vuelo, id_tipo_asiento, asientos_totales, asientos_disponibles)
            VALUES (%s,1,150,150),(%s,2,30,30),(%s,3,10,10)
        """, (id_vuelo_t, id_vuelo_t, id_vuelo_t))
        conn.commit()

    # Consultar vuelos ya existentes para esa ruta y fecha
    cur.execute("""
        SELECT v.id_vuelo, v.origen, v.destino, v.fecha_salida,
               v.hora_salida, v.hora_llegada, v.duracion_min,
               v.precio_base, v.vuelo_internacional,
               a2.nombre AS aerolinea,
               SUM(ia.asientos_disponibles) AS total_disponibles
        FROM vuelo v
        JOIN avion av       ON av.id_avion     = v.id_avion
        JOIN aerolinea a2   ON a2.id_aerolinea = av.id_aerolinea
        JOIN inventario_asientos ia ON ia.id_vuelo = v.id_vuelo
        WHERE v.origen = %s AND v.destino = %s AND v.fecha_salida = %s
        GROUP BY v.id_vuelo
        ORDER BY v.hora_salida
    """, (origen, destino, fecha))
    lista_vuelos = cur.fetchall()

    cur.close(); conn.close()

    return render_template("vuelos.html",
                           vuelos=lista_vuelos,
                           origen=origen,
                           destino=destino,
                           fecha=fecha)


# ─────────────────────────────────────────────
#  WIZARD PASO 3 — ELEGIR ASIENTO/CLASE
# ─────────────────────────────────────────────
@app.route("/asiento/<int:id_vuelo>")
@login_required
def asiento(id_vuelo):
    conn = get_db()
    cur  = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT v.*, a2.nombre AS aerolinea
        FROM vuelo v
        JOIN avion av     ON av.id_avion     = v.id_avion
        JOIN aerolinea a2 ON a2.id_aerolinea = av.id_aerolinea
        WHERE v.id_vuelo = %s
    """, (id_vuelo,))
    vuelo = cur.fetchone()

    if not vuelo:
        flash("Vuelo no encontrado.", "danger")
        return redirect(url_for("buscar"))

    cur.execute("""
        SELECT ta.id_tipo_asiento, ta.descripcion,
               ta.porcentaje_incremento, ta.precio_base,
               ia.asientos_disponibles,
               ROUND(v.precio_base * (1 + ta.porcentaje_incremento/100), 2) AS precio_final
        FROM inventario_asientos ia
        JOIN tipo_asiento ta ON ta.id_tipo_asiento = ia.id_tipo_asiento
        JOIN vuelo v ON v.id_vuelo = ia.id_vuelo
        WHERE ia.id_vuelo = %s
        ORDER BY ta.porcentaje_incremento
    """, (id_vuelo,))
    clases = cur.fetchall()
    cur.close(); conn.close()

    return render_template("asiento.html", vuelo=vuelo, clases=clases)


# ─────────────────────────────────────────────
#  WIZARD PASO 4 — RESUMEN Y PAGO
# ─────────────────────────────────────────────
@app.route("/pagar/<int:id_vuelo>/<int:id_tipo_asiento>", methods=["GET", "POST"])
@login_required
def pagar(id_vuelo, id_tipo_asiento):
    conn = get_db()
    cur  = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT v.*, a2.nombre AS aerolinea,
               ROUND(v.precio_base * (1 + ta.porcentaje_incremento/100), 2) AS precio_final,
               ta.descripcion AS clase
        FROM vuelo v
        JOIN avion av       ON av.id_avion       = v.id_avion
        JOIN aerolinea a2   ON a2.id_aerolinea   = av.id_aerolinea
        JOIN tipo_asiento ta ON ta.id_tipo_asiento = %s
        WHERE v.id_vuelo = %s
    """, (id_tipo_asiento, id_vuelo))
    vuelo = cur.fetchone()

    if not vuelo:
        flash("Vuelo no encontrado.", "danger")
        cur.close(); conn.close()
        return redirect(url_for("buscar"))

    if request.method == "POST":
        try:
            # 1. Crear reservación
            cur.execute("""
                INSERT INTO reservacion (id_usuario, id_vuelo, id_tipo_asiento)
                VALUES (%s, %s, %s)
            """, (session["id_usuario"], id_vuelo, id_tipo_asiento))
            conn.commit()
            id_reservacion = cur.lastrowid

            # 2. Registrar pago
            cur.execute("""
                INSERT INTO pago (id_reservacion, monto, metodo_pago, fecha_pago, aprobado)
                VALUES (%s, %s, 'Tarjeta', NOW(), TRUE)
            """, (id_reservacion, vuelo["precio_final"]))
            conn.commit()

            # 3. Generar código de boleto
            codigo_boleto = f"AS-{__import__('datetime').date.today().year}-{str(id_reservacion).zfill(6)}"

            # 4. Emitir boleto
            cur.execute("""
                INSERT INTO boleto (id_usuario, id_vuelo, id_tipo_asiento,
                                    id_reservacion, codigo_boleto, costo_base, costo_final)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (session["id_usuario"], id_vuelo, id_tipo_asiento,
                  id_reservacion, codigo_boleto,
                  vuelo["precio_base"], vuelo["precio_final"]))
            conn.commit()

            cur.close(); conn.close()
            flash(f"¡Pago confirmado! Tu código de boleto es {codigo_boleto}", "success")
            return redirect(url_for("mis_viajes"))

        except MySQLError as e:
            conn.rollback()
            flash(f"Error al procesar el pago: {e.msg}", "danger")
            cur.close(); conn.close()
            return redirect(url_for("pagar", id_vuelo=id_vuelo, id_tipo_asiento=id_tipo_asiento))

    cur.close(); conn.close()
    return render_template("pagar.html", vuelo=vuelo,
                           id_tipo_asiento=id_tipo_asiento)


# ─────────────────────────────────────────────
#  MIS VIAJES
# ─────────────────────────────────────────────
@app.route("/mis-viajes")
@login_required
def mis_viajes():
    conn = get_db()
    cur  = conn.cursor(dictionary=True)

    # Boletos confirmados
    cur.execute("""
        SELECT b.id_boleto, b.codigo_boleto, b.costo_final, b.fecha_compra,
               v.origen, v.destino, v.fecha_salida, v.hora_salida, v.hora_llegada,
               ta.descripcion AS clase, r.estado, r.id_reservacion
        FROM boleto b
        JOIN vuelo        v  ON v.id_vuelo         = b.id_vuelo
        JOIN tipo_asiento ta ON ta.id_tipo_asiento  = b.id_tipo_asiento
        JOIN reservacion  r  ON r.id_reservacion    = b.id_reservacion
        WHERE b.id_usuario = %s
        ORDER BY b.fecha_compra DESC
    """, (session["id_usuario"],))
    boletos = cur.fetchall()

    # Reservaciones pendientes (sin boleto aún)
    cur.execute("""
        SELECT r.id_reservacion, r.fecha_reserva, r.fecha_expiracion,
               v.origen, v.destino, v.fecha_salida, ta.descripcion AS clase
        FROM reservacion r
        JOIN vuelo        v  ON v.id_vuelo        = r.id_vuelo
        JOIN tipo_asiento ta ON ta.id_tipo_asiento = r.id_tipo_asiento
        WHERE r.id_usuario = %s AND r.estado = 'pendiente'
        ORDER BY r.fecha_reserva DESC
    """, (session["id_usuario"],))
    pendientes = cur.fetchall()

    cur.close(); conn.close()
    return render_template("mis_viajes.html", boletos=boletos, pendientes=pendientes)


# ─────────────────────────────────────────────
#  CANCELAR
# ─────────────────────────────────────────────
@app.route("/cancelar/<int:id_reservacion>", methods=["GET", "POST"])
@login_required
def cancelar(id_reservacion):
    conn = get_db()
    cur  = conn.cursor(dictionary=True)

    cur.execute("""
        SELECT r.*, v.origen, v.destino, v.fecha_salida,
               ta.descripcion AS clase
        FROM reservacion r
        JOIN vuelo        v  ON v.id_vuelo        = r.id_vuelo
        JOIN tipo_asiento ta ON ta.id_tipo_asiento = r.id_tipo_asiento
        WHERE r.id_reservacion = %s AND r.id_usuario = %s
    """, (id_reservacion, session["id_usuario"]))
    reservacion = cur.fetchone()

    if not reservacion:
        flash("Reservación no encontrada.", "danger")
        cur.close(); conn.close()
        return redirect(url_for("mis_viajes"))

    if request.method == "POST":
        motivo = request.form.get("motivo", "Sin motivo")
        try:
            cur.callproc("sp_cancelar_reservacion", (
                id_reservacion,
                session["id_usuario"],
                motivo
            ))
            conn.commit()
            cur.close(); conn.close()
            flash("Tu reservación fue cancelada. Si realizaste un pago, el reembolso será procesado.", "success")
            return redirect(url_for("mis_viajes"))
        except MySQLError as e:
            flash(f"No se pudo cancelar: {e.msg}", "danger")
            cur.close(); conn.close()
            return redirect(url_for("mis_viajes"))

    cur.close(); conn.close()
    return render_template("cancelar.html", reservacion=reservacion)

@app.route("/debug")
def debug():
    return f"id_usuario en sesión: {session.get('id_usuario')} | nombre: {session.get('nombre')}"

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────
if __name__ == "__main__":
    app.run(debug=True)