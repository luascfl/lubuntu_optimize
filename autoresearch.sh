#!/bin/bash
set -euo pipefail

# Captura o total de pressao antes
BEFORE=$(grep "some" /proc/pressure/memory | awk '{print $5}' | cut -d= -f2)

# Calcula a memoria disponivel e adiciona 500 MiB para forçar swap sem esgotar o sistema
AVAILABLE_MIB=$(free -m | awk '/^Mem\.:/{print $7}')
WORKLOAD_MIB=$((AVAILABLE_MIB + 500))

# Inicia carga dinamica por 30 segundos
./run-memory-pressure-workload.sh $WORKLOAD_MIB 30 > /dev/null &
PID=$!

# Aguarda o tempo do teste
wait $PID

# Captura o total de pressao depois
AFTER=$(grep "some" /proc/pressure/memory | awk '{print $5}' | cut -d= -f2)

DELTA=$((AFTER - BEFORE))

echo "METRIC memory_pressure=$DELTA"
