clear all;
device = serialport("COM16",115200,'Parity','none','DataBits',8,'StopBits',1);

N_ELEMENTS= 1024;  
BIT_WIDTH = 10;

%% Vectores

vecA = randi([0, 2^BIT_WIDTH - 1], N_ELEMENTS, 1);
vecB = randi([0, 2^BIT_WIDTH - 1], N_ELEMENTS, 1);

% Referencias
% Producto Punto
host_dotProd = dot(vecA,vecB);

% Distancia Euclidiana
host_eucDist = sqrt(sum((double(vecA) - double(vecB)).^2));

%% CARGA DE VECTORES EN DEVICE
fprintf('ESCRIBIENDO VECTORES\n');

write2dev(device, vecA, 'BRAMA');
fprintf('Vector A cargado.\n');

write2dev(device, vecB, 'BRAMB');
fprintf('Vector B cargado.\n');

%% VERIFICACIÓN VECTORES
vecA_rb = command2dev(device, 'readVec', 'BRAMA', N_ELEMENTS);
vecB_rb = command2dev(device, 'readVec', 'BRAMB', N_ELEMENTS);

if isequal(vecA, vecA_rb) && isequal(vecB, vecB_rb)
    fprintf('Vectores son iguales\n');
else
    fprintf('Error en lectura de vectores\n');
end

%% PRODUCTO PUNTO
fprintf('----------------------------------------\n');
fprintf('PRODUCTO PUNTO\n');

raw_dot = command2dev(device, 'dotProd', [], 0);
dev_dot_val = double(raw_dot);

% Resultados
fprintf('Referencia Host : %.0f\n', host_dotProd);
fprintf('Resultado Device    : %.0f\n', dev_dot_val);
fprintf('Diferencia        : %.0f\n', abs(host_dotProd - dev_dot_val));
fprintf('----------------------------------------\n');
fprintf('DISPLAY HEX: %08X\n', raw_dot);
pause(1)


%% DISTANCIA EUCLIDIANA (Q16.16)
fprintf('----------------------------------------\n');
fprintf('DIST. EUCLIDIANA (Q16.16)\n');

raw_euc = command2dev(device, 'eucDist', [], 0);

% Para la representación Q16.16
dev_euc_val = double(raw_euc) / 65536;

% Resultados
fprintf('Referencia Host : %.4f\n', host_eucDist);
fprintf('Resultado Device    : %.4f\n', dev_euc_val);
fprintf('Diferencia        : %.4f\n', abs(host_eucDist - dev_euc_val));

% Formato visual para comparar con el display 7Seg
hex_upper = bitshift(raw_euc, -16);      % Parte Entera
hex_lower = bitand(raw_euc, 65535);      % Parte Decimal
fprintf('----------------------------------------\n');
fprintf('DISPLAY HEX: %04X.%04X\n', hex_upper, hex_lower);

%%
clear device;

fprintf('\nPruebas finalizadas. Puerto cerrado.\n');
