% Practica UART: MATLAB envia A y n; la DE10-Lite calcula floor(A^(n/2)).
% n acepta CUALQUIER ENTERO NO NEGATIVO en notacion decimal (sin limite 8).
% MATLAB NO hace potencias, raices ni division para el resultado.
% Protocolo: 1 byte A + n decimal ASCII + LF (10).
% Respuesta: 1 byte STATUS + 4 bytes uint32 LITTLE ENDIAN.
%   STATUS=0: OK; 1: OVERFLOW (>uint32); 2: ENTRADA INVALIDA.
clear;
clc;

PORT = "COM22";  % Cambiar SOLO si el ESP32 tiene otro COM.
BAUD = 9600;
TIMEOUT = 5.0;

try
    anterior = serialportfind;
    if ~isempty(anterior)
        delete(anterior);
    end
catch
end

s = serialport(PORT, BAUD);
s.Timeout = TIMEOUT;
pause(2); % ESP32 puede reiniciar al abrir el COM.
flush(s);

fprintf('==============================================\n');
fprintf('MATLAB -> ESP32 -> DE10-Lite -> MATLAB\n');
fprintf('La FPGA calcula floor(A^(n/2)) SIN division.\n');
fprintf('A: entero de 0 a 255\n');
fprintf('n: cualquier entero >= 0 (sin limite a 8)\n');
fprintf('Si no cabe en 32 bits: OVERFLOW.\n');
fprintf('Puerto %s | 9600 baudios | 8N1\n', PORT);
fprintf('==============================================\n\n');

while true
    txtA = strtrim(input('A (0..255, q para salir): ', 's'));
    if strcmpi(txtA, 'q'), break; end
    A = str2double(txtA);
    if isempty(txtA) || ~isfinite(A) || A < 0 || A > 255 || A ~= floor(A)
        disp('ERROR: A debe ser entero entre 0 y 255.');
        continue;
    end

    txtN = strtrim(input('n (entero >= 0, sin limite a 8): ', 's'));
    if isempty(regexp(txtN, '^[0-9]+$', 'once'))
        disp('ERROR: n debe ser entero no negativo (solo digitos).');
        continue;
    end

    % Codificacion: un byte de A y los digitos decimales de n con LF final.
    % No convertimos n a double: un entero largo NO pierde cifras.
    solicitud = [uint8(A), uint8(txtN), uint8(10)];
    flush(s, 'input');
    write(s, solicitud, 'uint8');
    fprintf('Enviado: A=%d, n=%s\n', A, txtN);

    bytes = zeros(1, 5, 'uint8');
    cantidad = 0;
    t = tic;
    while cantidad < 5 && toc(t) < TIMEOUT
        disponibles = min(double(s.NumBytesAvailable), 5 - cantidad);
        if disponibles > 0
            parte = read(s, disponibles, 'uint8');
            bytes(cantidad + 1:cantidad + disponibles) = reshape(parte, 1, []);
            cantidad = cantidad + disponibles;
        else
            pause(0.005);
        end
    end

    if cantidad ~= 5
        fprintf('SIN RESPUESTA COMPLETA: llegaron %d de 5 bytes.\n', cantidad);
        fprintf('Comprueba el nuevo .sof, el ESP32 y el puerto COM.\n\n');
        continue;
    end

    status = bytes(1);
    if status == 0
        respuesta = uint32(bytes(2));
        respuesta = bitor(respuesta, bitshift(uint32(bytes(3)), 8));
        respuesta = bitor(respuesta, bitshift(uint32(bytes(4)), 16));
        respuesta = bitor(respuesta, bitshift(uint32(bytes(5)), 24));
        fprintf('Resultado calculado por FPGA: %u\n', respuesta);
    elseif status == 1
        fprintf('OVERFLOW: A^(n/2) excede 32 bits.\n');
        fprintf('El exponente se acepto; el resultado es demasiado grande.\n');
    elseif status == 2
        fprintf('FPGA: entrada no valida.\n');
    else
        fprintf('ERROR DE PROTOCOLO: status %u.\n', status);
    end
    fprintf('----------------------------------------------\n\n');
end

clear s;
disp('Puerto cerrado.');
