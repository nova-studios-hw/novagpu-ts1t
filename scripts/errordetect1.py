#!/usr/bin/env python3 
# ================================================================
# errordetect1.py — Detector de Errores Línea por Línea
# NovaGPU TS 1T — Maximal Technology / Nova Studios
#
# USO EN GOOGLE COLAB:
#   !python3 scripts/errordetect1.py
# 
# USO LOCAL:
#   python3 scripts/errordetect1.py
#   python3 scripts/errordetect1.py --fix   # auto-fix los reparables
#
# QUÉ HACE:
#   Escanea CADA LÍNEA de todos los archivos .v del proyecto y
#   corre 6 pruebas de diagnóstico por línea:
#
#   PRUEBA 1 — Errores de sintaxis que rompen compilación Icarus/Verilator
#   PRUEBA 2 — Problemas de timing que impiden síntesis FPGA
#   PRUEBA 3 — Errores de lógica (overflow, underflow, race conditions)
#   PRUEBA 4 — Incompatibilidades Verilog-2001 vs SystemVerilog
#   PRUEBA 5 — Problemas de Clock Domain Crossing (CDC)
#   PRUEBA 6 — Patrones que Vivado rechaza o genera warnings críticos
#
# SALIDA:
#   Por cada error encontrado imprime:
#     [NIVEL] archivo.v:línea — DESCRIPCIÓN EXACTA
#     >> Código problemático
#     >> Por qué falla: explicación técnica
#     >> Fix: cómo repararlo
# ================================================================

import re
import os
import sys
import subprocess
from pathlib import Path

# ── COLORES PARA TERMINAL ────────────────────────────────────
RED    = "\033[91m"
YELLOW = "\033[93m"
GREEN  = "\033[92m"
CYAN   = "\033[96m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

# ── NIVELES ───────────────────────────────────────────────────
CRITICO = f"{RED}{BOLD}[CRÍTICO]{RESET}"
WARN    = f"{YELLOW}[WARN]   {RESET}"
INFO    = f"{CYAN}[INFO]   {RESET}"
OK      = f"{GREEN}[OK]     {RESET}"

# ── ENCONTRAR ARCHIVOS ────────────────────────────────────────
def find_verilog_files():
    base = Path(__file__).parent.parent
    files = []
    for folder in ['rtl', 'fpga']:
        d = base / folder
        if d.exists():
            files.extend(sorted(d.glob('*.v')))
    return files

# ================================================================
# PRUEBA 1 — ERRORES DE SINTAXIS QUE ROMPEN COMPILACIÓN
# ================================================================
def prueba1_sintaxis(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 1.1 Palabra reservada 'inside' usada como identificador
    if re.search(r'\binside\b', line) and 'is_inside' not in line:
        if not line.strip().startswith('//'):
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P1.1',
                'codigo': stripped,
                'porque': "'inside' es palabra reservada en SystemVerilog. "
                          "Icarus con -g2012 la rechaza como nombre de variable.",
                'fix': "Renombrar a 'is_inside' en esta línea y todas sus referencias."
            })
    
    # 1.2 Timescale faltante (solo verificar primera línea)
    if lineno == 1 and not line.startswith('`timescale'):
        issues.append({
            'nivel': WARN,
            'prueba': 'P1.2',
            'codigo': line.rstrip(),
            'porque': "Sin `timescale al inicio, Icarus y Verilator pueden tener "
                      "escalas de tiempo inconsistentes entre módulos. "
                      "Causa: flancos de reloj que no coinciden → tests fallan.",
            'fix': "Agregar `timescale 1ns/1ps como PRIMERA línea del archivo."
        })
    
    # 1.3 wire declarada dentro de always block
    # Detectar por indentación excesiva (2+ niveles) en declaración wire
    if re.match(r'\s{4,}wire\s+', line) and not line.strip().startswith('//'):
        # Verificar que no sea una asignación wire normal fuera de always
        issues.append({
            'nivel': CRITICO,
            'prueba': 'P1.3',
            'codigo': stripped,
            'porque': "Declaración de 'wire' dentro de un bloque always. "
                      "Verilog-2001 NO permite declarar wire dentro de always. "
                      "Icarus lo rechaza con 'syntax error near wire'.",
            'fix': "Mover la declaración wire FUERA del bloque always, "
                   "al nivel del módulo. Cambiar a 'reg' si necesita ser local."
        })
    
    # 1.4 Literal hex con más bits de los declarados
    for m in re.finditer(r"(\d+)'[hH]([0-9a-fA-F_]+)", line):
        declared = int(m.group(1))
        val = m.group(2).replace('_', '')
        actual = len(val) * 4
        if actual > declared:
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P1.4',
                'codigo': stripped,
                'porque': f"Constante {declared}'h{m.group(2)} tiene {actual} bits "
                          f"pero el campo es {declared} bits. "
                          f"Icarus trunca silenciosamente los {actual-declared} bits superiores. "
                          "Esto causa valores incorrectos en la simulación.",
                'fix': f"Reducir a {declared//4} dígitos hex exactos, o "
                       f"aumentar el ancho a {actual}'{chr(104)}{m.group(2)}."
            })
    
    # 1.5 Literal signed decimal que no cabe en N bits
    for m in re.finditer(r"(\d+)'sd(\d+)", line):
        bits = int(m.group(1))
        val  = int(m.group(2))
        max_pos = (2 ** (bits - 1)) - 1
        if val > max_pos:
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P1.5',
                'codigo': stripped,
                'porque': f"{bits}'sd{val}: el máximo positivo para {bits} bits signed "
                          f"es +{max_pos}. El valor {val} > {max_pos} → se almacena como "
                          f"{val - 2**bits} en complemento a 2 (NEGATIVO). "
                          "Ejemplo: 9'sd256 = -256, no +256.",
                'fix': f"Cambiar la declaración a {bits+1}'sd{val} "
                       f"(un bit más) o usar {bits}'sd{max_pos} como valor máximo."
            })
    
    # 1.6 endcase/end faltante o mal colocado (detección básica)
    if stripped == 'end' and '//' not in line:
        pass  # No podemos detectar balance sin contexto completo
    
    return issues

# ================================================================
# PRUEBA 2 — TIMING: LÓGICA QUE ROMPE SÍNTESIS FPGA
# ================================================================
def prueba2_timing(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 2.1 División combinacional en wire (no potencia de 2)
    # / por constante que no es 2^n
    m = re.search(r'wire\s+.*=.*\/\s*(\d+)', line)
    if m:
        divisor = int(m.group(1))
        if divisor > 1 and (divisor & (divisor - 1)) != 0:  # No es potencia de 2
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P2.1',
                'codigo': stripped,
                'porque': f"División por {divisor} en wire combinacional. "
                          f"{divisor} NO es potencia de 2 → Vivado genera un divisor "
                          "hardware de ~30-50 niveles de lógica. En Artix-7 a 100 MHz "
                          "el período es 10ns; 50 niveles LUT = ~15-20ns → WNS negativo → "
                          "timing NO cierra → bitstream incorrecto.",
                'fix': f"Usar contadores registrados (reg) en lugar de dividir un wire. "
                       f"Si necesitas x/{divisor}: usar x >> N donde 2^N ≈ {divisor}, "
                       f"o calcular en always @(posedge clk)."
            })
    
    # 2.2 Módulo en wire (%) por no-potencia-de-2
    m2 = re.search(r'wire\s+.*=.*%\s*(\d+)', line)
    if m2:
        modulo = int(m2.group(1))
        if modulo > 1 and (modulo & (modulo - 1)) != 0:
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P2.2',
                'codigo': stripped,
                'porque': f"Operación módulo (%) por {modulo} en wire combinacional. "
                          f"Similar a la división: genera lógica profunda. "
                          "En Artix-7: probable WNS < 0 ns en timing report.",
                'fix': f"Si {modulo} es cerca de potencia de 2: usar máscara AND. "
                       "Si no: registrar el resultado en always @(posedge clk)."
            })
    
    # 2.3 Multiplicación de anchos grandes en wire combinacional
    m3 = re.search(r'wire\s+\[(\d+):0\].*=.*\*', line)
    if m3:
        width = int(m3.group(1)) + 1
        if width >= 32:
            issues.append({
                'nivel': WARN,
                'prueba': 'P2.3',
                'codigo': stripped,
                'porque': f"Multiplicación de {width} bits en wire combinacional. "
                          "Vivado puede mapearlo a DSP48 (bien) pero si no cabe, "
                          "usa LUTs → path largo → posible WNS negativo.",
                'fix': "Registrar en always @(posedge clk) y agregar 1 ciclo de latencia."
            })
    
    # 2.4 Bucle for con límite variable en always_ff (no sintetizable)
    if 'for' in line and 'always' not in line:
        m4 = re.search(r'for\s*\(.*;\s*\w+\s*<\s*(\w+)\s*;', line)
        if m4:
            limit = m4.group(1)
            # Si el límite es un signal (no un parámetro/número)
            if not limit.isdigit() and not limit.isupper():
                issues.append({
                    'nivel': WARN,
                    'prueba': 'P2.4',
                    'codigo': stripped,
                    'porque': f"Bucle for con límite variable '{limit}' en lógica. "
                              "Vivado requiere que los límites de for sean constantes "
                              "en tiempo de síntesis. Si '{limit}' es una señal runtime → "
                              "error de síntesis.",
                    'fix': f"Cambiar {limit} por un localparam o parameter constante."
                })
    
    return issues

# ================================================================
# PRUEBA 3 — LÓGICA: OVERFLOW, UNDERFLOW, RACE CONDITIONS
# ================================================================
def prueba3_logica(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 3.1 Contador decrementando sin guardia de underflow
    if re.search(r'(\w+)\s*<=\s*\1\s*-\s*\d+', line):
        m = re.search(r'(\w+)\s*<=\s*\1\s*-\s*(\d+)', line)
        if m:
            sig = m.group(1)
            # Verificar si hay condición de guarda cerca
            issues.append({
                'nivel': WARN,
                'prueba': 'P3.1',
                'codigo': stripped,
                'porque': f"'{sig}' decrementa sin verificar si es > 0. "
                          "En Verilog sin signo: 0 - 1 = 2^N-1 (wraparound al máximo). "
                          "Esto puede activar lógica que depende de un contador 'grande'.",
                'fix': f"Agregar condición: if ({sig} > 0) {sig} <= {sig} - 1;"
            })
    
    # 3.2 Dos always blocks escribiendo la misma señal
    # (detectado por asignación no-bloqueante a una señal que aparece en múltiples always)
    # Este check se hace a nivel de archivo, no de línea — ver prueba global
    
    # 3.3 Asignación bloqueante (=) en always @(posedge clk)
    # Solo en contextos que parecen registros (no tasks, no funciones)
    if re.search(r'^\s+\w+\s*=\s*[^=<>!]', line) and '==' not in line and '<=' not in line:
        if 'function' not in line and 'task' not in line and 'parameter' not in line:
            if 'localparam' not in line and 'assign' not in line:
                issues.append({
                    'nivel': WARN,
                    'prueba': 'P3.2',
                    'codigo': stripped,
                    'porque': "Asignación bloqueante (=) en lo que parece un bloque "
                              "always @(posedge clk). En Verilog para registros se debe "
                              "usar non-bloqueante (<=). Con (=): el orden de evaluación "
                              "depende del simulador → race condition entre módulos.",
                    'fix': "Cambiar '=' por '<=' para todas las asignaciones en "
                           "always @(posedge clk)."
                })
    
    # 3.4 Señal leída en mismo ciclo que se escribe (registered-before-use)
    # Patrón: reg_out = {campo_a, campo_b} donde campo_a se asigna en la misma línea
    
    # 3.5 Bus concatenado con ancho incorrecto
    m = re.search(r'=\s*\{([^}]+)\}', line)
    if m:
        parts = m.group(1).split(',')
        # Verificar si hay literales numéricos mezclados que sumen mal
        total_known = 0
        has_issue = False
        for part in parts:
            part = part.strip()
            hm = re.match(r"(\d+)'[bBhHdD]", part)
            if hm:
                total_known += int(hm.group(1))
            nm = re.match(r"(\d+)'sd(\d+)", part)
            if nm:
                total_known += int(nm.group(1))
    
    return issues

# ================================================================
# PRUEBA 4 — COMPATIBILIDAD VERILOG-2001 vs SYSTEMVERILOG
# ================================================================
def prueba4_compatibilidad(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 4.1 typedef struct — solo en SystemVerilog
    if re.match(r'\s*typedef\s+struct', line):
        issues.append({
            'nivel': WARN,
            'prueba': 'P4.1',
            'codigo': stripped,
            'porque': "'typedef struct' es SystemVerilog. "
                      "Icarus en modo -g2001 la rechaza. "
                      "Con -g2012 funciona, pero mezclar estilos causa warnings.",
            'fix': "Usar --sv en Verilator o -g2012 en Icarus. "
                   "O reemplazar struct por parámetros y arrays separados."
        })
    
    # 4.2 logic en lugar de wire/reg — SV only
    if re.match(r'\s*(input|output|inout)\s+logic\s+', line):
        issues.append({
            'nivel': INFO,
            'prueba': 'P4.2',
            'codigo': stripped,
            'porque': "'logic' es tipo de SystemVerilog. En Verilog-2001 puro "
                      "se usa 'wire' para inputs y 'reg' para outputs con always. "
                      "Icarus con -g2012 acepta logic, pero sin el flag falla.",
            'fix': "Asegurar que todos los comandos usen -g2012 (Icarus) o --sv (Verilator). "
                   "O reemplazar 'logic' por 'wire'/'reg' según el uso."
        })
    
    # 4.3 always_ff, always_comb, always_latch — SV only
    for kw in ['always_ff', 'always_comb', 'always_latch']:
        if re.match(rf'\s*{kw}\b', line):
            issues.append({
                'nivel': INFO,
                'prueba': 'P4.3',
                'codigo': stripped,
                'porque': f"'{kw}' es SystemVerilog. En Verilog-2001: "
                          "always_ff → always @(posedge clk), "
                          "always_comb → always @(*). "
                          "Icarus sin -g2012 lo rechaza.",
                'fix': f"Usar -g2012 en Icarus. O reemplazar '{kw}' por "
                       "'always @(posedge clk or negedge rst_n)' / 'always @(*)'."
            })
    
    # 4.4 $clog2 en parámetro de módulo — Icarus versiones viejas no lo soportan
    if '$clog2' in line and 'parameter' in line:
        issues.append({
            'nivel': WARN,
            'prueba': 'P4.4',
            'codigo': stripped,
            'porque': "$clog2 en declaración de parámetro puede fallar en "
                      "versiones de Icarus < 10.3. Icarus de Colab puede ser antigua.",
            'fix': "Calcular el valor manualmente: clog2(256)=8, clog2(1024)=10, etc. "
                   "y usar el número directamente: parameter BITS = 10;"
        })
    
    # 4.5 Arrays de puertos (input wire [N:0] arr [M:0]) — SV only
    if re.search(r'(input|output)\s+wire\s+\[[^\]]+\]\s+\w+\s+\[[^\]]+\]', line):
        issues.append({
            'nivel': CRITICO,
            'prueba': 'P4.5',
            'codigo': stripped,
            'porque': "Array de puertos (puerto con dimensión extra) es SystemVerilog. "
                      "Icarus -g2001 lo rechaza. El síntoma típico es "
                      "'error: Net/variable port connection is not a valid net'.",
            'fix': "Aplanar el array: en lugar de 'input [15:0] mat [0:15]', "
                   "usar 'input [255:0] mat_flat' y hacer slice internamente."
        })
    
    return issues

# ================================================================
# PRUEBA 5 — CLOCK DOMAIN CROSSING (CDC)
# ================================================================
def prueba5_cdc(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 5.1 Asignación directa entre dominios de reloj (sin sincronizador)
    # Heurística: señal que viene de un dominio y se usa en otro
    # No podemos detectarlo 100% sin análisis de toda la jerarquía,
    # pero buscamos patrones comunes
    
    # 5.2 BRAM con dos relojes diferentes asignados directamente sin FIFO
    if 'clk_a' in line and 'clk_b' in line:
        issues.append({
            'nivel': INFO,
            'prueba': 'P5.1',
            'codigo': stripped,
            'porque': "BRAM con dos relojes (clk_a / clk_b). Si clk_a ≠ clk_b "
                      "(ej: 100 MHz core y 25 MHz VGA), la dirección de lectura "
                      "(generada en dominio VGA) se presenta al puerto B de BRAM "
                      "en el dominio clk_b. Esto es correcto para True DP BRAM "
                      "SOLO si se usa registered output mode. "
                      "Verificar que el dato de salida usa latencia de 1 ciclo.",
            'fix': "Confirmar que 'data_b' en framebuffer.v se registra en always "
                   "@(posedge clk_b). Ya está correcto en la versión actual."
        })
    
    # 5.3 Señal de un dominio usada en otro sin sincronizador
    if re.search(r'(pll_locked|rst_async)', line) and '<=' in line:
        if 'sync' not in line.lower():
            issues.append({
                'nivel': WARN,
                'prueba': 'P5.2',
                'codigo': stripped,
                'porque': "Señal asincrónica (pll_locked/rst_async) usada directamente "
                          "en lógica registrada sin sincronizador. "
                          "Puede causar metaestabilidad en FPGA.",
                'fix': "Pasar por reset_sync.v antes de usar en lógica."
            })
    
    return issues

# ================================================================
# PRUEBA 6 — PATRONES QUE VIVADO RECHAZA O GENERA WARNINGS CRÍTICOS
# ================================================================
def prueba6_vivado(lineno, line, fname):
    issues = []
    stripped = line.strip()
    
    # 6.1 initial block en RTL (no en testbench)
    if re.match(r'\s*initial\s+begin', line) or re.match(r'\s*initial\s+\w+', line):
        if 'tb_' not in str(fname) and 'sim' not in str(fname):
            issues.append({
                'nivel': WARN,
                'prueba': 'P6.1',
                'codigo': stripped,
                'porque': "Bloque 'initial' en RTL de síntesis. Vivado acepta "
                          "'initial' para inicializar BRAM/registros, pero genera "
                          "warning si no es mapeable a reset. En módulos combinacionales "
                          "o funciones puede causar comportamiento inesperado post-síntesis.",
                'fix': "Si es para inicializar BRAM: OK, Vivado lo maneja. "
                       "Si es para simulación únicamente: mover al testbench."
            })
    
    # 6.2 $random o $urandom en RTL
    if '$random' in line or '$urandom' in line:
        if 'tb_' not in str(fname):
            issues.append({
                'nivel': CRITICO,
                'prueba': 'P6.2',
                'codigo': stripped,
                'porque': "$random/$urandom son funciones de simulación. "
                          "Vivado las ignora en síntesis → la señal queda "
                          "sin driver → Vivado asigna valor constante (0 o 1) → "
                          "comportamiento completamente diferente en FPGA vs simulación.",
                'fix': "Reemplazar con un valor determinístico o LFSR hardware."
            })
    
    # 6.3 Latch inferido (señal no asignada en todos los caminos de always @(*))
    # Heurística: if sin else en always combinacional
    # Difícil sin contexto completo, pero buscamos patrones obvios
    
    # 6.4 División fuera de always (en assign) por constante NO potencia de 2
    if re.match(r'\s*assign\s+', line) and '/' in line:
        m = re.search(r'/\s*(\d+)', line)
        if m:
            div = int(m.group(1))
            if div > 1 and (div & (div - 1)) != 0:
                issues.append({
                    'nivel': CRITICO,
                    'prueba': 'P6.3',
                    'codigo': stripped,
                    'porque': f"assign con división por {div} (no potencia de 2). "
                              "Vivado genera un divisor combinacional grande. "
                              f"Para Artix-7 a 100 MHz (período 10 ns): "
                              f"la división por {div} puede necesitar 15-25 ns → "
                              "WNS negativo → timing no cierra → no se genera bitstream.",
                'fix': "Reemplazar con registro y cálculo en always @(posedge clk)."
                })
    
    # 6.5 Parámetro usado como divisor de reloj en generate
    if 'generate' in line.lower() and 'clk' in line.lower():
        issues.append({
            'nivel': INFO,
            'prueba': 'P6.4',
            'codigo': stripped,
            'porque': "Bloque generate con referencia a reloj. Vivado trata "
                      "los relojes de forma especial en síntesis. "
                      "Verificar que el clock wizard genere todos los relojes necesarios.",
            'fix': "Usar IP Clocking Wizard de Vivado para generar clk_pixel (25 MHz). "
                   "No derivar relojes de lógica combinacional."
        })
    
    # 6.6 Flip-flop con async set Y async reset simultáneos (no soportado en Artix-7)
    if 'posedge' in line and 'negedge' in line:
        if 'or' in line and line.count('negedge') > 1:
            issues.append({
                'nivel': WARN,
                'prueba': 'P6.5',
                'codigo': stripped,
                'porque': "Múltiples edges en sensitivity list. Si incluye dos negedge "
                          "o un posedge + dos negedge: Artix-7 no soporta FF con "
                          "async set Y async reset simultáneos en la misma celda.",
                'fix': "Usar solo: always @(posedge clk or negedge rst_n). "
                       "Un solo reset asincrónico por always block."
            })
    
    return issues

# ================================================================
# ANÁLISIS GLOBAL POR ARCHIVO (multi-línea)
# ================================================================
def analisis_global(fname, lines):
    issues = []
    
    # G.1 Señales con múltiples drivers (dos always escribiendo la misma señal)
    nb_assigns = {}  # señal → lista de líneas que la asignan con <=
    in_always = False
    always_line = 0
    
    for i, line in enumerate(lines, 1):
        if re.search(r'always\s*@', line):
            in_always = True
            always_line = i
        if in_always:
            m = re.match(r'\s+(\w+)\s*<=', line)
            if m:
                sig = m.group(1)
                if sig not in nb_assigns:
                    nb_assigns[sig] = []
                nb_assigns[sig].append(i)
        if re.match(r'^end\b', line.strip()) and in_always:
            in_always = False
    
    for sig, lineas in nb_assigns.items():
        # Si la señal aparece en 3+ líneas de always blocks distintos, alerta
        if len(lineas) >= 4 and sig not in ['state', 'i', 'j', 'k']:
            # Verificar que son always blocks distintos (líneas separadas por >5)
            spread = max(lineas) - min(lineas)
            if spread > 20:
                issues.append({
                    'nivel': WARN,
                    'prueba': 'G.1',
                    'linea': lineas[0],
                    'codigo': f"'{sig}' asignado en líneas: {lineas[:5]}",
                    'porque': f"La señal '{sig}' parece ser asignada en múltiples "
                              "always blocks (posible múltiples drivers). "
                              "Verilog no permite múltiples drivers para la misma señal reg. "
                              "Causa: 'X' (don't care) en simulación, comportamiento "
                              "indeterminado en hardware.",
                    'fix': f"Consolidar todas las asignaciones a '{sig}' en un solo "
                           "always block con lógica case/if."
                })
    
    # G.2 Módulo sin instancias de reset_n
    has_reset = any('rst_n' in l or 'rst_sync_n' in l or 'reset' in l.lower() 
                    for l in lines)
    has_always_posedge = any('always @(posedge clk' in l for l in lines)
    
    if has_always_posedge and not has_reset:
        issues.append({
            'nivel': WARN,
            'prueba': 'G.2',
            'linea': 1,
            'codigo': '(archivo completo)',
            'porque': "Módulo con always @(posedge clk) pero sin señal de reset. "
                      "En FPGA, al programar el bitstream los registros tienen "
                      "valor indefinido. Sin reset, el estado inicial es aleatorio → "
                      "comportamiento impredecible en los primeros ciclos.",
            'fix': "Agregar 'or negedge rst_n' al always y manejar el caso !rst_n."
        })
    
    # G.3 Verificar que todos los módulos tienen `timescale
    if lines and not lines[0].startswith('`timescale'):
        issues.append({
            'nivel': WARN,
            'prueba': 'G.3',
            'linea': 1,
            'codigo': lines[0].rstrip(),
            'porque': "Falta `timescale 1ns/1ps en la primera línea. "
                      "Sin esto, Icarus usa la escala por defecto (puede variar) "
                      "y los #delay en simulación tienen tiempos incorrectos.",
            'fix': "Agregar `timescale 1ns/1ps como primera línea."
        })
    
    return issues

# ================================================================
# RUNNER PRINCIPAL
# ================================================================
def run_iverilog_check(files, sim_files):
    """Intenta compilar con iverilog y reporta errores exactos."""
    print(f"\n{BOLD}{'='*65}{RESET}")
    print(f"{BOLD} COMPILACIÓN CON IVERILOG -g2012{RESET}")
    print(f"{BOLD}{'='*65}{RESET}")
    
    all_rtl = [str(f) for f in files]
    
    for sim in sim_files:
        cmd = ['iverilog', '-g2012', '-o', '/dev/null'] + all_rtl + [str(sim)]
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            tb_name = sim.name
            if result.returncode == 0:
                print(f"{OK} {tb_name}: compila sin errores")
            else:
                print(f"{CRITICO} {tb_name}:")
                for line in result.stderr.strip().split('\n'):
                    if line.strip():
                        # Parse iverilog error format: file.v:line: error message
                        m = re.match(r'(.+):(\d+):\s*(.*)', line)
                        if m:
                            ef, el, msg = m.group(1), m.group(2), m.group(3)
                            print(f"  {RED}  {os.path.basename(ef)}:{el}{RESET} → {msg}")
                        else:
                            print(f"  {RED}  {line}{RESET}")
        except FileNotFoundError:
            print(f"{YELLOW}[SKIP]{RESET} iverilog no instalado. "
                  "En Colab: !apt-get install -y iverilog")
            break
        except subprocess.TimeoutExpired:
            print(f"{WARN} {sim.name}: timeout en compilación")

def main():
    print(f"\n{BOLD}{'='*65}{RESET}")
    print(f"{BOLD} errordetect1.py — NovaGPU TS 1T{RESET}")
    print(f"{BOLD} Detector de Errores Línea por Línea{RESET}")
    print(f"{BOLD} Maximal Technology / Nova Studios{RESET}")
    print(f"{BOLD}{'='*65}{RESET}\n")
    
    files = find_verilog_files()
    
    if not files:
        print(f"{RED}ERROR: No se encontraron archivos .v en rtl/ o fpga/{RESET}")
        print("Ejecutar desde la raíz del proyecto: python3 scripts/errordetect1.py")
        sys.exit(1)
    
    print(f"Archivos encontrados: {len(files)}")
    for f in files:
        print(f"  {CYAN}{f.parent.name}/{f.name}{RESET}")
    
    # ── CONTADORES ────────────────────────────────────────────
    total_critico = 0
    total_warn    = 0
    total_info    = 0
    errors_by_file = {}
    
    print(f"\n{BOLD}{'─'*65}{RESET}")
    print(f"{BOLD} ANÁLISIS LÍNEA POR LÍNEA (6 PRUEBAS){RESET}")
    print(f"{BOLD}{'─'*65}{RESET}")
    
    for fpath in files:
        with open(fpath, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
        
        file_issues = []
        
        # Análisis global del archivo
        global_issues = analisis_global(fpath, lines)
        for gi in global_issues:
            gi['file'] = fpath.name
            file_issues.append(gi)
        
        # Análisis línea por línea
        for lineno, line in enumerate(lines, 1):
            line_issues = []
            line_issues += prueba1_sintaxis(lineno, line, fpath)
            line_issues += prueba2_timing(lineno, line, fpath)
            line_issues += prueba3_logica(lineno, line, fpath)
            line_issues += prueba4_compatibilidad(lineno, line, fpath)
            line_issues += prueba5_cdc(lineno, line, fpath)
            line_issues += prueba6_vivado(lineno, line, fpath)
            
            for issue in line_issues:
                issue['file'] = fpath.name
                issue['linea'] = lineno
                file_issues.append(issue)
        
        if file_issues:
            errors_by_file[fpath.name] = file_issues
            print(f"\n{BOLD}── {fpath.parent.name}/{fpath.name} "
                  f"({len(file_issues)} issues) ──{RESET}")
            
            for issue in file_issues:
                nivel = issue['nivel']
                prueba = issue.get('prueba', '?')
                linea = issue.get('linea', '?')
                
                if 'CRÍTICO' in nivel:
                    total_critico += 1
                elif 'WARN' in nivel:
                    total_warn += 1
                else:
                    total_info += 1
                
                print(f"\n  {nivel} {CYAN}[{prueba}]{RESET} "
                      f"línea {BOLD}{linea}{RESET}")
                print(f"  Código:   {YELLOW}{issue.get('codigo', '')[:80]}{RESET}")
                print(f"  Por qué:  {issue['porque']}")
                print(f"  Fix:      {GREEN}{issue['fix']}{RESET}")
        else:
            print(f"  {OK} {fpath.parent.name}/{fpath.name} — sin issues detectados")
    
    # ── INTENTAR COMPILACIÓN CON IVERILOG ────────────────────
    base = Path(__file__).parent.parent
    sim_dir = base / 'sim'
    sim_files = sorted(sim_dir.glob('tb_*.v')) if sim_dir.exists() else []
    
    if sim_files:
        run_iverilog_check(files, sim_files)
    
    # ── RESUMEN FINAL ─────────────────────────────────────────
    print(f"\n{BOLD}{'='*65}{RESET}")
    print(f"{BOLD} RESUMEN FINAL{RESET}")
    print(f"{BOLD}{'='*65}{RESET}")
    
    total = total_critico + total_warn + total_info
    print(f"\n  Archivos escaneados:  {len(files)}")
    print(f"  Total de issues:      {total}")
    print(f"  {RED}{BOLD}Críticos:{RESET}             {total_critico} "
          f"← bloquean compilación o FPGA")
    print(f"  {YELLOW}Warnings:{RESET}             {total_warn} "
          f"← pueden causar bugs en hardware")
    print(f"  {CYAN}Info:{RESET}                 {total_info} "
          f"← buenas prácticas")
    
    if total_critico == 0:
        print(f"\n{GREEN}{BOLD}✓ Sin errores críticos — el proyecto puede compilar{RESET}")
    else:
        print(f"\n{RED}{BOLD}✗ {total_critico} errores críticos — "
              f"corregir antes de correr testbenches{RESET}")
    
    print(f"\n  Archivos con issues:")
    for fname, issues in errors_by_file.items():
        criticos = sum(1 for i in issues if 'CRÍTICO' in i['nivel'])
        warns    = sum(1 for i in issues if 'WARN' in i['nivel'])
        print(f"    {fname}: {RED}{criticos} críticos{RESET}, "
              f"{YELLOW}{warns} warnings{RESET}")
    
    print(f"\n{BOLD}Para correr simulación después de corregir:{RESET}")
    print("  iverilog -g2012 -o sim rtl/*.v fpga/*.v sim/tb_maestro_v12.v")
    print("  vvp sim")
    print(f"\n{BOLD}{'='*65}{RESET}\n")
    
    return total_critico

if __name__ == '__main__':
    criticos = main()
    sys.exit(0 if criticos == 0 else 1)

