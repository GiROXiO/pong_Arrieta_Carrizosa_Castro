LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

ENTITY moduloLogica IS
	PORT (
		clk_50Mhz : IN std_logic;
		reset     : IN std_logic;
		
		-- Coordenadas y bandera desde moduloVGA
		pixel_x  : IN std_logic_vector(9 DOWNTO 0);
		pixel_y  : IN std_logic_vector(9 DOWNTO 0);
		video_on : IN std_logic;
		
		-- Botones desde moduloDecodificador
		p1_up   : IN std_logic;
		p1_down : IN std_logic;
		p2_up   : IN std_logic;
		p2_down : IN std_logic;
		
		-- Salida de color hacia el monitor (8 bits por color para la placa Altera)
		vga_r : OUT std_logic_vector(7 DOWNTO 0);
		vga_g : OUT std_logic_vector(7 DOWNTO 0);
		vga_b : OUT std_logic_vector(7 DOWNTO 0);
		
		-- Puntaje
		score_p1 : OUT std_logic;
		score_p2 : OUT std_logic
	);
END moduloLogica;

ARCHITECTURE behavioral OF moduloLogica IS

	-- Constantes del area de juego
	CONSTANT max_x : integer := 640;
	CONSTANT max_y : integer := 480;
	
	-- Dimensiones de los objetos
	CONSTANT pad_w  : integer := 16; -- Ancho de las paletas
	CONSTANT pad_h  : integer := 80; -- Alto de las paletas
	CONSTANT ball_s : integer := 10; -- Pelota cuadrada
	
	-- Velocidad de los objetos (pixeles por cada cuadro a 60hz
	CONSTANT pad_v  : integer := 5;
	CONSTANT ball_v : integer := 4;
	
	-- Posiciones fijas en x de las paletas
	CONSTANT p1_x : integer := 32;
	CONSTANT p2_x : integer := max_x - 32 - pad_w;
	
	-- Registros dinamicos de posicion (arrancan en el centro)
	SIGNAL p1_y   : integer := (max_y - pad_h)/2;
	SIGNAL p2_y   : integer := (max_y - pad_h)/2;
	SIGNAL ball_x : integer := max_x /2;
	SIGNAL ball_y : integer := max_y / 2;
	
	-- Registros dinamicos de velocidad de la pelota
	SIGNAL ball_vx : integer := ball_v;
	SIGNAL ball_vy : integer := ball_v;
	
	-- Tick de refresco
	SIGNAL refr_tick : std_logic;
	SIGNAL prev_refr_tick : std_logic := '0';
	
BEGIN
	
	-- Se genera un pulso exacto una vez por cuadro cuando el barrido llega a abajo
	-- Se garantiza que los objetos se muevan a 60 fps y no 50 millones de veces por segundo
	refr_tick <= '1' WHEN (unsigned(pixel_x) = 0 AND unsigned(pixel_y) = 480) ELSE '0';
	
	-- 1. Fisica y movimiento (actualizaciones de posiciones)
	PROCESS(clk_50Mhz, reset)
	BEGIN
		IF reset = '0' THEN
			p1_y    <= (max_y - pad_h) / 2;
         p2_y    <= (max_y - pad_h) / 2;
         ball_x  <= max_x / 2;
         ball_y  <= max_y / 2;
         ball_vx <= ball_v;
         ball_vy <= ball_v;
         score_p1 <= '0';
         score_p2 <= '0';	
			prev_refr_tick <= '0';
		ELSIF rising_edge(clk_50Mhz) THEN	
			score_p1 <= '0'; -- Por defecto en 0, solo se disparan un instante
         score_p2 <= '0';
			prev_refr_tick <= refr_tick;
            
         IF refr_tick = '1' AND prev_refr_tick = '0' THEN
				-- Control Paleta 1 (Limita que no salga de la pantalla)
            IF p1_up = '1' AND p1_y > 0 THEN
					p1_y <= p1_y - pad_v;
            ELSIF p1_down = '1' AND p1_y < (max_y - pad_h) THEN
					p1_y <= p1_y + pad_v;
            END IF;

            -- Control Paleta 2
            IF p2_up = '1' AND p2_y > 0 THEN
					p2_y <= p2_y - pad_v;
            ELSIF p2_down = '1' AND p2_y < (max_y - pad_h) THEN
               p2_y <= p2_y + pad_v;
            END IF;

            -- Movimiento Pelota (Eje Y: Rebote con techo y piso)
            IF ball_y <= 0 THEN
					ball_vy <= ball_v; -- Invierte hacia abajo
					ball_y <= ball_v;
					
            ELSIF ball_y >= (max_y - ball_s) THEN
               ball_vy <= -ball_v; -- Invierte hacia arriba
					ball_y <= max_y - ball_s - ball_v;
					
            ELSE
               ball_y <= ball_y + ball_vy;
            END IF;
				
				-- Movimiento Pelota (Eje X: Rebote con paletas o anota punto)
            -- Colision Paleta 1
            IF (ball_x <= p1_x + pad_w) AND (ball_x + ball_s >= p1_x) AND
               (ball_y + ball_s >= p1_y) AND (ball_y <= p1_y + pad_h) THEN
					ball_vx <= ball_v; -- Rebota hacia la derecha
					ball_x <= p1_x + pad_w + ball_v;
                    
            -- Colision Paleta 2
            ELSIF (ball_x + ball_s >= p2_x) AND (ball_x <= p2_x + pad_w) AND
                  (ball_y + ball_s >= p2_y) AND (ball_y <= p2_y + pad_h) THEN
					ball_vx <= -ball_v; -- Rebota hacia la izquierda
					ball_x <= p2_x - ball_s - ball_v;
                    
            -- Salio por la izquierda (Punto para Jugador 2)
            ELSIF ball_x <= 0 THEN
					ball_x <= max_x / 2;
               ball_y <= max_y / 2;
               score_p2 <= '1'; -- Dispara el pulso al marcador
                    
            -- Salio por la derecha (Punto para Jugador 1)
            ELSIF ball_x >= (max_x - ball_s) THEN
               ball_x <= max_x / 2;
               ball_y <= max_y / 2;
               score_p1 <= '1'; -- Dispara el pulso al marcador
                    
            -- Sigue moviendose libremente en X
            ELSE
               ball_x <= ball_x + ball_vx;
            END IF;
			END IF;
		END IF;
	END PROCESS;
	
	-- 2. Dibujo (se envian los colores al monitor)
	PROCESS(pixel_x, pixel_y, video_on, p1_y, p2_y, ball_x, ball_y)
		VARIABLE px : integer;
		VARIABLE py : integer;
	BEGIN
		px := to_integer(unsigned(pixel_x));
      py := to_integer(unsigned(pixel_y));

      -- Por defecto, pantalla apagada (negro)
      vga_r <= (OTHERS => '0');
      vga_g <= (OTHERS => '0');
      vga_b <= (OTHERS => '0');
		
		IF video_on = '1' THEN
			-- ¿El pixel actual pertenece a la Paleta 1? (Pintar Blanco)
         IF (px >= p1_x AND px < p1_x + pad_w) AND (py >= p1_y AND py < p1_y + pad_h) THEN
				vga_r <= (OTHERS => '1');
            vga_g <= (OTHERS => '1');
            vga_b <= (OTHERS => '1');
                
         -- ¿El pixel actual pertenece a la Paleta 2? (Pintar Blanco)
         ELSIF (px >= p2_x AND px < p2_x + pad_w) AND (py >= p2_y AND py < p2_y + pad_h) THEN
            vga_r <= (OTHERS => '1');
            vga_g <= (OTHERS => '1');
            vga_b <= (OTHERS => '1');
                
         -- ¿El pixel actual pertenece a la Pelota? (Pintar Blanco)
         ELSIF (px >= ball_x AND px < ball_x + ball_s) AND (py >= ball_y AND py < ball_y + ball_s) THEN
            vga_r <= (OTHERS => '1');
            vga_g <= (OTHERS => '1');
            vga_b <= (OTHERS => '1');
			END IF;
      END IF;
	END PROCESS;
	
END behavioral;