function result = command2dev(device, op, target, n_elems)
    cmd = 0;
    is_vector_read = false;
    
    switch op
        case 'readVec'
            is_vector_read = true;
            if strcmp(target, 'BRAMA'), cmd = 3; else, cmd = 4; end
        case 'dotProd', cmd = 6;
        case 'eucDist', cmd = 7;
    end
    
    write(device, cmd, "uint8");
    
    if is_vector_read
        % Leer N * 2 bytes
        raw = read(device, n_elems * 2, "uint8");
        mat = reshape(raw, 2, n_elems);
        msb = uint16(mat(1, :));
        lsb = uint16(mat(2, :));
        result = double(bitor(bitshift(msb, 8), lsb))';
    else
        raw = read(device, 4, "uint8");
        if isempty(raw)
            result = 0;
        else
            % Reconstruir uint32 Little Endian
            result = double(raw(1)) + ...
                     double(raw(2)) * 256 + ...
                     double(raw(3)) * 65536 + ...
                     double(raw(4)) * 16777216;
            
            % Convertir a uint32 real para operaciones de bits
            result = uint32(result); 
        end
    end
end