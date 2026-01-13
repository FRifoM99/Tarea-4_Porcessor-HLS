function write2dev(device, data_vector, target)
    % Seleccionar comando (1=A, 2=B)
    if strcmp(target, 'BRAMA'), cmd = 1; else, cmd = 2; end
    
    % Convertir a uint16
    data_u16 = uint16(data_vector);
    
    % Separar MSB y LSB (Protocolo de 2 bytes)
    msb = uint8(bitshift(data_u16, -8));
    lsb = uint8(bitand(data_u16, 255));
    
    % Intercalar [MSB, LSB, MSB, LSB...]
    payload = [msb'; lsb'];
    payload = payload(:);
    
    write(device, cmd, "uint8"); % Enviar comando
    pause(0.01); 
    write(device, payload, "uint8"); % Enviar datos
    flush(device);
    pause(0.1); 
end