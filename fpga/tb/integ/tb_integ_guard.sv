//
// tb_integ_guard.sv -- V9990TANG: banco del POR, el gestor del rPLL base, el
// detector de perdida de enganche, la guardia de lock y el LED de estado.
//
// BSD 3-Clause License. Copyright (c) 2026, Papipapito.
//
// Modulos reales: BOARD_WT200B_GUARD, SYSTEM_RESET, SYSTEM_RESET_HOLD y
// STATUS_LED, con sus parametros de la build salvo el divisor del LED
// (BITS = 13 en lugar de 25: los mismos patrones, 4096 veces mas deprisa).
// Modelados: el rPLL base (LOCK que tarda, que se pierde o que no llega; en
// sync engancha solo con el reloj del slot entre 3 y 5,2 MHz, el rango de PFD
// y VCO del GW2AR-18 C8/I7 con x30 y ODIV 8), CLK_BASE, el READY de
// sdram.sv, el DONE del borrado de la megaROM y el /WAIT logico del V9990. En
// los pines, el /WAIT que saca el top: BOOT_HOLD || (DRIVE_EN && wait).
//
// Uso: tb/integ/run.sh (Verilator 5.020, --timing). Un binario por variante
// (-GSYNC=0 / -GSYNC=1) y un escenario por ejecucion (+SCEN=...):
//   lento    LOCK a los 3 ms de soltar el reset del rPLL
//   perdida  xtal: un hueco de LOCK de 50 us (los pines se sueltan, sin
//            reset) y una perdida de 1 ms; sync: el reloj del slot se para
//            2 ms (el siguiente arranque es en frio)
//   nunca    xtal: el rPLL no engancha nunca; sync: sin reloj del slot
//   turbo    solo sync: reloj del slot a 5,37 MHz (fuera de rango)
//   tope     el rPLL engancha y la SDRAM no da READY hasta los 70 ms
//   mega     configuracion MegaRAM: el borrado tarda 2 ms
//   timeout  WAIT_TIMEOUT pegajoso despues de arrancar
//   glitch   LOCK con tres huecos de 10 us mientras engancha (UG286: LOCK
//            puede dar glitches al enganchar): PLL_OK solo tras 2,43 ms de
//            LOCK seguido despues del ultimo hueco, y una sola vez
//   turbo_marcha  el reloj del slot pasa a 5,37 MHz con el sistema listo y
//            vuelve a los 2 ms: en sync, pines sueltos en cuanto cae LOCK,
//            reset y reenganche; en xtal, nada
// En todos: /WAIT retenido (BOOT_HOLD) desde el fin de la configuracion (xtal)
// o desde el primer flanco del reloj del slot (sync) hasta que el sistema
// queda listo, sin huecos y como mucho 50 ms; DRIVE_EN nunca sin PLL_OK ni con
// LOCK bajo mas de 3 ciclos de 27 MHz.
//

`timescale 1ns/1ps
`default_nettype none

module tb_integ_guard #(
    parameter int SYNC = 0
);
    localparam int LED_BITS = 13;
    localparam real T27     = 37.037;                       // ns
    localparam real TBASE   = (SYNC != 0) ? 9.3122 : 9.2593;       // ns

    /***************************************************************
     * Escenario
     ***************************************************************/
    string scen;
    initial begin
        if(!$value$plusargs("SCEN=%s", scen)) scen = "lento";
        $display("== tb_integ_guard SYNC=%0d SCEN=%s", SYNC, scen);
    end

    int n_pass = 0;
    int n_fail = 0;
    task automatic check(input bit cond, input string what);
        if(cond) begin n_pass++; $display("PASA   %10.3f us  %s", $realtime / 1000.0, what); end
        else     begin n_fail++; $display("FALLA  %10.3f us  %s", $realtime / 1000.0, what); end
    endtask

    /***************************************************************
     * Relojes
     ***************************************************************/
    logic clk27 = 1'b0;
    always #(T27 / 2.0) clk27 = ~clk27;

    // reloj del slot: on/off y periodo (ns)
    bit   slot_on     = 1'b1;
    real  slot_period = 279.365;
    logic slot_clk    = 1'b0;
    initial begin
        forever begin
            if(slot_on) begin
                #(slot_period / 2.0) slot_clk = ~slot_clk;
            end
            else begin
                slot_clk = 1'b0;
                wait(slot_on);
            end
        end
    end

    /***************************************************************
     * Modelo del rPLL base
     ***************************************************************/
    logic pll_reset;
    logic pll_lock   = 1'b0;
    bit   pll_run    = 1'b0;
    bit   pll_never  = 1'b0;          // no engancha nunca
    bit   pll_unlock = 1'b0;          // fuerza LOCK = 0 (huecos y perdidas)
    real  pll_lock_delay = 3_000_000.0;   // ns desde reset suelto con entrada valida hasta LOCK

    // entrada valida: xtal siempre (cristal); sync, reloj del slot presente y
    // en el rango del rPLL (3 a 5,2 MHz); se pierde 5 us despues de pararse
    realtime last_slot_edge = 0.0;
    always @(posedge slot_clk) last_slot_edge = $realtime;
    function automatic bit pll_in_ok();
        if(SYNC == 0) return 1'b1;
        return slot_on && ($realtime - last_slot_edge < 5000.0)
               && (slot_period >= 192.3) && (slot_period <= 333.4);
    endfunction

    real t_ok = 0.0;    // tiempo con el reset suelto y la entrada valida
    always #100.0 begin
        if(pll_reset) begin
            pll_run  = 1'b0;
            pll_lock = 1'b0;
            t_ok     = 0.0;
        end
        else begin
            pll_run = 1'b1;
            if(pll_in_ok() && !pll_never && !pll_unlock) begin
                if(t_ok >= pll_lock_delay) pll_lock = 1'b1;
                else                       t_ok = t_ok + 100.0;
            end
            else begin
                pll_lock = 1'b0;
                if(!pll_in_ok()) t_ok = 0.0;
            end
        end
    end

    logic clk_base = 1'b0;
    initial begin
        forever begin
            if(pll_run) begin
                #(TBASE / 2.0) clk_base = ~clk_base;
            end
            else begin
                clk_base = 1'b0;
                wait(pll_run);
            end
        end
    end

    /***************************************************************
     * Disenyo: guardia (CLK_27M) y cadena de reset (CLK_BASE)
     ***************************************************************/
    logic pll_ok, drive_en, boot_hold, por_done, slot_ok, slot_present;
    logic sys_ready_27, hold_expired, relocked, wto_27;
    logic sys_reset_n;
    logic wait_timeout = 1'b0;

    BOARD_WT200B_GUARD #(
        .SYNC           (SYNC)
    ) u_guard (
        .CLK_27M        (clk27),
        .PLL_LOCK       (pll_lock),
        .SLOT_CLK       (slot_clk),
        .SYS_READY      (sys_reset_n),
        .WAIT_TIMEOUT   (wait_timeout),
        .PLL_RESET      (pll_reset),
        .PLL_OK         (pll_ok),
        .DRIVE_EN_27    (drive_en),
        .BOOT_HOLD_27   (boot_hold),
        .POR_DONE       (por_done),
        .SLOT_OK        (slot_ok),
        .SLOT_PRESENT   (slot_present),
        .SYS_READY_27   (sys_ready_27),
        .HOLD_EXPIRED   (hold_expired),
        .RELOCKED       (relocked),
        .WAIT_TIMEOUT_27(wto_27)
    );

    logic base_ready, reset_n, sdram_ready = 1'b0;
    SYSTEM_RESET u_rst (
        .CLK            (clk_base),
        .PLL_OK         (pll_ok),
        .SDRAM_READY    (sdram_ready),
        .BASE_READY     (base_ready),
        .RESET_n        (reset_n)
    );

    // READY de sdram.sv: unos 33 ciclos despues de su reset (aqui 40)
    int  sd_cnt = 0;
    real sdram_ready_after = 0.0;     // ns de simulacion antes de los cuales la SDRAM no acaba nunca
    always @(posedge clk_base or negedge base_ready) begin
        if(!base_ready) begin
            sd_cnt      <= 0;
            sdram_ready <= 1'b0;
        end
        else if($realtime >= sdram_ready_after) begin
            if(sd_cnt == 40) sdram_ready <= 1'b1;
            else             sd_cnt      <= sd_cnt + 1;
        end
    end

    // MEGAROM_CLEAR: DONE CLEAR_CYCLES ciclos despues de RESET_n
    bit mega = 1'b0;
    int clear_cycles = 0;
    int cl_cnt = 0;
    logic clear_done = 1'b0;
    always @(posedge clk_base or negedge reset_n) begin
        if(!reset_n) begin
            cl_cnt     <= 0;
            clear_done <= 1'b0;
        end
        else if(!mega || cl_cnt == clear_cycles) clear_done <= 1'b1;
        else                                     cl_cnt     <= cl_cnt + 1;
    end
    wire clear_hold = mega ? !clear_done : 1'b0;

    SYSTEM_RESET_HOLD u_sysrst (
        .CLK            (clk_base),
        .RESET_n        (reset_n),
        .HOLD           (clear_hold),
        .SYS_RESET_n    (sys_reset_n)
    );

    logic led;
    logic [2:0] led_code;
    STATUS_LED #(
        .SYNC           (SYNC),
        .BITS           (LED_BITS)
    ) u_led (
        .CLK            (clk27),
        .PLL_OK         (pll_ok),
        .SYS_READY      (sys_ready_27),
        .SLOT_PRESENT   (slot_present),
        .WAIT_TIMEOUT   (wto_27),
        .RELOCKED       (relocked),
        .LED            (led),
        .CODE           (led_code)
    );

    // /WAIT en el pin (CART_WAIT_n = 1 activa el transistor): el gateo del top
    bit  v99_wait = 1'b1;                       // /WAIT logico del V9990 (peor caso: pedido)
    wire wait_pin = boot_hold || (drive_en && v99_wait);

    /***************************************************************
     * Vigilancia continua (en cada flanco de CLK_27M)
     ***************************************************************/
    // arranque en frio segun el banco: desde el principio hasta que el sistema
    // queda listo; en sync, otra vez cuando se para el reloj del slot
    bit tb_cold = 1'b1;
    always @(posedge drive_en) tb_cold = 1'b0;
    always @(negedge slot_on) if(SYNC != 0) tb_cold = 1'b1;

    int viol_drive = 0, viol_hold = 0, viol_mute = 0, viol_reset = 0, viol_both = 0, both_run = 0;
    int lock_low = 0;               // ciclos de 27 MHz seguidos con LOCK bajo (antes de este flanco)
    logic pll_ok_q = 1'b0;
    always @(posedge clk27) begin
        // sin enganche (ciclo anterior): sin DRIVE_EN
        if(!pll_ok_q && drive_en) viol_drive++;
        // sin enganche: BOOT_HOLD solo en el arranque en frio (en sync, con
        // reloj del slot)
        if(!pll_ok_q && boot_hold && !(tb_cold && (SYNC == 0 || slot_on))) viol_hold++;
        // LOCK bajo: DRIVE_EN cae como mucho 3 ciclos despues
        if(drive_en && lock_low > 3) viol_mute++;
        // sin enganche: el sistema en reset (la afirmacion es asincrona)
        if(!pll_ok && sys_reset_n) viol_reset++;
        // relevo BOOT_HOLD -> DRIVE_EN: solapados como mucho un ciclo
        if(drive_en && boot_hold) begin both_run++; if(both_run > 1) viol_both++; end
        else both_run = 0;
        lock_low = pll_lock ? 0 : lock_low + 1;
        pll_ok_q <= pll_ok;
    end

    // huecos de /WAIT con el V9990 pidiendolo: el pin no puede bajar mientras
    // el PLL siga enganchado ni durante el arranque en frio
    int wait_gaps = 0;
    always @(negedge wait_pin) if((pll_ok || tb_cold) && v99_wait && !hold_expired && $time > 0) wait_gaps++;

    // pulsos de reset del rPLL, subidas de PLL_OK y bajadas de SYS_RESET_n
    int pll_reset_rises = 0;
    always @(posedge pll_reset) pll_reset_rises++;
    int pll_ok_rises = 0;
    realtime t_pllok = 0.0;
    always @(posedge pll_ok) begin pll_ok_rises++; t_pllok = $realtime; end
    int sysrst_falls = 0;
    always @(negedge sys_reset_n) if($time > 0) sysrst_falls++;
    realtime t_drive_fall = 0.0;
    always @(negedge drive_en) t_drive_fall = $realtime;

    // BOOT_HOLD: subidas, duracion de cada pulso y el mas largo
    int      hold_rises = 0;
    realtime hold_rise = 0.0, hold_len = 0.0, hold_max = 0.0, hold_first = -1.0;
    always @(posedge boot_hold) begin
        hold_rises++;
        hold_rise = $realtime;
        if(hold_first < 0.0) hold_first = $realtime;
    end
    always @(negedge boot_hold) begin
        hold_len = $realtime - hold_rise;
        if(hold_len > hold_max) hold_max = hold_len;
    end

    /***************************************************************
     * LED: subidas y tiempo encendido en un periodo del divisor
     ***************************************************************/
    task automatic led_window(output int rises, output real duty);
        int hi = 0;
        logic prev;
        rises = 0;
        prev = led;
        for(int i = 0; i < (1 << LED_BITS); i++) begin
            @(posedge clk27);
            if(led && !prev) rises++;
            if(led) hi++;
            prev = led;
        end
        duty = real'(hi) / real'(1 << LED_BITS);
    endtask

    task automatic check_led(input int code, input string what);
        int  rises;
        real duty;
        int  exp_rises;
        real exp_duty;
        case(code)
            0: begin exp_rises = 8; exp_duty = 0.5;   end   // rapido
            1: begin exp_rises = 2; exp_duty = 0.5;   end   // lento
            2: begin exp_rises = 1; exp_duty = 0.125; end   // destello corto
            3: begin exp_rises = 2; exp_duty = 0.25;  end   // doble destello
            4: begin exp_rises = 4; exp_duty = 0.25;  end   // cuatro destellos
            default: begin exp_rises = 0; exp_duty = 1.0; end   // fijo
        endcase
        led_window(rises, duty);
        check(led_code == 3'(code) && rises == exp_rises && (duty > exp_duty - 0.01) && (duty < exp_duty + 0.01),
              $sformatf("LED %s: codigo %0d (esperado %0d), %0d subidas y %0.3f encendido por periodo (esperado %0d y %0.3f)",
                        what, led_code, code, rises, duty, exp_rises, exp_duty));
    endtask

    task automatic wait_us(input real us);
        #(us * 1000.0);
    endtask

    task automatic check_invariants(input string when);
        check(viol_drive == 0, $sformatf("%s: DRIVE_EN a 0 siempre que el PLL no esta enganchado (%0d violaciones)", when, viol_drive));
        check(viol_hold  == 0, $sformatf("%s: BOOT_HOLD sin enganche solo en el arranque en frio (%0d violaciones)", when, viol_hold));
        check(hold_max < 50_010_000.0, $sformatf("%s: ningun BOOT_HOLD pasa de 50 ms (el mas largo, %0.4f ms)", when, hold_max / 1.0e6));
        check(viol_mute  == 0, $sformatf("%s: DRIVE_EN cae a los 3 ciclos de LOCK bajo como mucho (%0d violaciones)", when, viol_mute));
        check(viol_reset == 0, $sformatf("%s: SYS_RESET_n bajo siempre que el PLL no esta enganchado (%0d violaciones)", when, viol_reset));
        check(viol_both  == 0, $sformatf("%s: relevo BOOT_HOLD -> DRIVE_EN con solape de un ciclo como mucho (%0d violaciones)", when, viol_both));
        check(wait_gaps  == 0, $sformatf("%s: /WAIT del pin sin huecos con el V9990 pidiendolo, con el PLL enganchado o en el arranque en frio (%0d huecos)", when, wait_gaps));
    endtask

    // arranque en frio: BOOT_HOLD sube al empezar (xtal: el primer flanco de
    // 27 MHz; sync: el primer flanco del reloj del slot), una sola vez, y
    // baja cuando el sistema queda listo (t_end_us) o al tope
    task automatic check_cold_hold(input real t0_us, input real t_end_us, input int rises, input string what);
        real lim;
        lim = (SYNC != 0) ? 0.5 : 0.1;
        check(hold_rises == rises && (hold_rise / 1000.0 - t0_us) >= 0.0 && (hold_rise / 1000.0 - t0_us) < lim
              && ((hold_rise + hold_len) / 1000.0 - t_end_us) > -0.1 && ((hold_rise + hold_len) / 1000.0 - t_end_us) < 0.1,
              $sformatf("%s: BOOT_HOLD desde los %0.3f us (%0.3f us tras el inicio; limite %0.1f) hasta los %0.3f ms (esperado %0.3f), subidas %0d (esperadas %0d)",
                        what, hold_rise / 1000.0, hold_rise / 1000.0 - t0_us, lim, (hold_rise + hold_len) / 1.0e6, t_end_us / 1000.0, hold_rises, rises));
    endtask

    // espera a que el sistema quede listo, con tope; vuelve tres ciclos de
    // CLK_27M despues de DRIVE_EN (el relevo con BOOT_HOLD dura uno)
    task automatic wait_ready(input real max_us, output real at_us);
        realtime t0 = $realtime;
        while(!drive_en && ($realtime - t0) < max_us * 1000.0) @(posedge clk27);
        at_us = $realtime / 1000.0;
        repeat(3) @(posedge clk27);
        #1;
    endtask

    /***************************************************************
     * Escenarios
     ***************************************************************/
    real t_ready, t_lost, t_loss_ref, t_mute, t_back;
    real t_glitch_end = 0.0;

    initial begin
        #1;
        // ---------------- comun: arranque ----------------
        if(scen == "nunca") begin
            if(SYNC != 0) slot_on = 1'b0;            // sin reloj del slot: el rPLL ni se suelta
            else     pll_never = 1'b1;
        end
        else if(scen == "turbo") begin
            slot_period = 186.243;              // 5,369 MHz
        end
        else if(scen == "tope") begin
            sdram_ready_after = 70_000_000.0;   // la SDRAM no acaba hasta los 70 ms
        end
        else if(scen == "mega") begin
            mega = 1'b1;
            clear_cycles = (SYNC != 0) ? 214_772 : 216_000;   // 2 ms de borrado
        end

        // primeros 1,2 ms: POR, nada enganchado; el BOOT_HOLD del arranque en
        // frio ya retiene al MSX (xtal siempre; sync, con reloj del slot)
        wait_us(600.0);
        begin
            bit    exp_hold;
            string why, first;
            exp_hold = (SYNC == 0) || slot_on;
            why      = "arranque en frio";
            if(!exp_hold) why = "sin reloj del slot no hay MSX";
            first    = "xtal: primer flanco de 27 MHz";
            if(SYNC != 0) first = "sync: primer flanco del reloj del slot";
            check(!por_done && pll_reset && !pll_ok && !drive_en && boot_hold == exp_hold && !sys_reset_n,
                  $sformatf("durante el POR: rPLL en reset, sin PLL_OK ni DRIVE_EN, sistema en reset; BOOT_HOLD %0d (esperado %0d: %s)",
                            boot_hold, exp_hold, why));
            if(exp_hold)
                check(hold_rises == 1 && hold_first >= 0.0 && hold_first < ((SYNC != 0) ? 500.0 : 100.0),
                      $sformatf("arranque en frio: BOOT_HOLD sube a los %0.3f us de acabar la configuracion (%s)",
                                hold_first / 1000.0, first));
        end
        check_led(0, "durante el POR");

        if(scen == "glitch") begin
            // tres huecos de LOCK de 10 us, uno por milisegundo, desde que
            // LOCK sube por primera vez
            fork
                begin
                    wait(pll_lock);
                    for(int g = 0; g < 3; g++) begin
                        wait_us(1_000.0);
                        pll_unlock = 1'b1;
                        wait_us(10.0);
                        pll_unlock = 1'b0;
                    end
                    t_glitch_end = $realtime / 1000.0;
                end
            join_none
        end

        if(scen == "nunca" || scen == "turbo") begin
            wait_us(60_000.0);
            check(!pll_ok && !drive_en && !boot_hold && !sys_reset_n,
                  "a los 60 ms sin enganche: sin PLL_OK, DRIVE_EN ni BOOT_HOLD; sistema en reset (el cartucho mudo, el MSX arranca)");
            if(SYNC != 0 && scen == "nunca")
                check(hold_rises == 0,
                      $sformatf("sync sin reloj del slot (MSX apagado): ningun BOOT_HOLD (subidas: %0d)", hold_rises));
            else
                check(hold_rises == 1 && hold_expired && hold_len > 49_990_000.0 && hold_len < 50_010_000.0,
                      $sformatf("sin enganche: el BOOT_HOLD del arranque en frio dura %0.4f ms (tope de 50 ms) y suelta al MSX (subidas: %0d)",
                                hold_len / 1.0e6, hold_rises));
            if(SYNC != 0)
                check(pll_reset && pll_reset_rises == 0 && !slot_ok,
                      $sformatf("sync sin reloj del slot valido: el rPLL sigue en reset desde el POR (subidas de PLL_RESET: %0d, SLOT_OK %0d)", pll_reset_rises, slot_ok));
            else
                check(pll_reset_rises >= 3,
                      $sformatf("xtal sin LOCK: el gestor reintenta (reset del rPLL cada ~19,4 ms): %0d reintentos en 60 ms", pll_reset_rises));
            check_led(0, "sin enganche");
            check_invariants("sin enganche");
        end
        else begin
            // engancha a los 3 ms de soltar el reset (POR 1,21 ms; en sync
            // la ventana de medida del reloj del slot cabe dentro del POR) y
            // PLL_OK llega tras 2,43 ms de LOCK seguido
            wait_ready(scen == "mega" ? 11_000.0 : (scen == "glitch" ? 12_000.0 : 9_000.0), t_ready);

            if(scen == "tope") begin
                check(pll_ok && boot_hold && !drive_en && !sys_reset_n,
                      "tope: PLL enganchado, sistema sin acabar: BOOT_HOLD activo, sin DRIVE_EN");
                check_led(1, "arrancando");
                wait(!boot_hold);
                #1;
                check(hold_rises == 1 && hold_len > 49_990_000.0 && hold_len < 50_010_000.0 && hold_expired && !drive_en,
                      $sformatf("tope de BOOT_HOLD: %0.4f ms desde la configuracion (esperado 50 ms) y despues el MSX libre, cartucho mudo", hold_len / 1.0e6));
                check_led(1, "arrancando tras el tope (el arranque fallo)");
                wait_ready(25_000.0, t_ready);
                check(drive_en && !boot_hold && sys_reset_n && hold_rises == 1,
                      $sformatf("tope: el sistema acaba a los 70 ms: DRIVE_EN a los %0.3f ms sin volver a BOOT_HOLD", t_ready / 1000.0));
                check_led(5, "listo");
                check_invariants("tope");
            end
            else begin
                check(drive_en && sys_reset_n && !boot_hold,
                      $sformatf("arranque: listo a los %0.3f ms (DRIVE_EN, SYS_RESET_n, sin BOOT_HOLD)", t_ready / 1000.0));
                check_cold_hold(0.0, t_ready, 1, "arranque en frio");
                if(scen == "mega")
                    check((t_ready - t_pllok / 1000.0) > 1_900.0 && (t_ready - t_pllok / 1000.0) < 2_200.0,
                          $sformatf("mega: de PLL_OK a listo, el borrado de la megaROM: %0.3f ms", (t_ready - t_pllok / 1000.0) / 1000.0));
                else
                    check((t_ready - t_pllok / 1000.0) > 0.0 && (t_ready - t_pllok / 1000.0) < 2.0,
                          $sformatf("arranque: de PLL_OK a listo (SDRAM) %0.1f ns", t_ready * 1000.0 - t_pllok));
                begin
                    string extra;
                    extra = "";
                    if(scen == "mega") extra = " + borrado de 2 ms";
                    if(scen == "glitch")
                        check(t_glitch_end > 0.0 && (t_ready - t_glitch_end) > 2_420.0 && (t_ready - t_glitch_end) < 2_500.0 && pll_ok_rises == 1,
                              $sformatf("glitch: PLL_OK %0.3f ms despues del ultimo hueco de LOCK (esperado 2,43) y una sola subida de PLL_OK (%0d)",
                                        (t_ready - t_glitch_end) / 1000.0, pll_ok_rises));
                    else
                        check(t_ready > 6_550.0 && t_ready < (scen == "mega" ? 9_000.0 : 6_900.0) && pll_ok_rises == 1,
                              $sformatf("arranque: POR 1,21 ms + LOCK de 3 ms + 2,43 ms estable%s: %0.3f ms (subidas de PLL_OK: %0d)", extra, t_ready / 1000.0, pll_ok_rises));
                end
                v99_wait = 1'b0;
                check_led(5, "listo");
                check_invariants("arranque");

                if(scen == "timeout") begin
                    wait_timeout = 1'b1;
                    wait_us(1.0);
                    wait_timeout = 1'b0;
                    wait_us(1.0);
                    check(wto_27, "WAIT_TIMEOUT pegajoso visto en 27 MHz");
                    check_led(3, "listo con WAIT_TIMEOUT");
                    check(drive_en, "WAIT_TIMEOUT no quita DRIVE_EN");
                end

                if(scen == "perdida") begin
                    if(SYNC == 0) begin
                        // hueco corto de LOCK: los pines se sueltan en cuanto
                        // baja LOCK, pero sin perdida de enganche ni reset
                        t_loss_ref = $realtime;
                        pll_unlock = 1'b1;
                        wait_us(50.0);
                        pll_unlock = 1'b0;
                        t_mute = (t_drive_fall - t_loss_ref) / 1000.0;
                        check(t_mute > 0.0 && t_mute < 0.3,
                              $sformatf("hueco de LOCK de 50 us: DRIVE_EN cae a los %0.3f us (LOCK sin filtro)", t_mute));
                        wait_us(100.0);
                        check(pll_ok && drive_en && sys_reset_n && pll_ok_rises == 1 && sysrst_falls == 0,
                              $sformatf("hueco de LOCK de 50 us: sin perdida de enganche ni reset (bajadas de SYS_RESET_n: %0d); DRIVE_EN vuelve con LOCK", sysrst_falls));
                        // perdida larga
                        t_loss_ref = $realtime;
                        pll_unlock = 1'b1;
                        wait(!pll_ok);
                        t_lost = ($realtime - t_loss_ref) / 1000.0;
                        t_mute = (t_drive_fall - t_loss_ref) / 1000.0;
                        check(t_lost > 150.0 && t_lost < 155.0,
                              $sformatf("perdida de LOCK: PLL_OK cae a los %0.2f us (LOCK bajo 4096 ciclos seguidos)", t_lost));
                        check(t_mute > 0.0 && t_mute < 0.3,
                              $sformatf("perdida de LOCK: los pines se sueltan a los %0.3f us, sin esperar al filtro", t_mute));
                    end
                    else begin
                        // el reloj del slot desaparece
                        t_loss_ref = $realtime;
                        slot_on = 1'b0;
                        wait(!pll_ok);
                        t_lost = ($realtime - t_loss_ref) / 1000.0;
                        @(posedge clk27); @(posedge clk27); #1;
                        t_mute = (t_drive_fall - t_loss_ref) / 1000.0;
                        check(t_lost < 2.0 && t_mute > 0.0 && t_mute < 2.0,
                              $sformatf("reloj del slot parado: PLL_OK cae a los %0.3f us y DRIVE_EN a los %0.3f us", t_lost, t_mute));
                    end
                    @(posedge clk27); @(posedge clk27); #1;
                    check(!drive_en && !boot_hold && !sys_reset_n && !reset_n && !base_ready,
                          "tras la perdida: DRIVE_EN y BOOT_HOLD a 0, sistema en reset");
                    check_led(0, "perdida");
                    // vuelve
                    wait_us((SYNC != 0) ? 2_000.0 : 1_000.0);
                    t_back = $realtime / 1000.0;
                    if(SYNC != 0) slot_on = 1'b1; else pll_unlock = 1'b0;
                    wait_ready(9_000.0, t_ready);
                    check(drive_en && sys_reset_n && relocked,
                          $sformatf("reenganche: listo otra vez a los %0.3f ms y RELOCKED", t_ready / 1000.0));
                    if(SYNC != 0)
                        check_cold_hold(t_back, t_ready, 2, "sync, vuelve el reloj del slot (MSX encendido otra vez: arranque en frio)");
                    else
                        check(hold_rises == 2 && hold_rise >= t_pllok && hold_len > 0.0 && hold_len < 2_000.0,
                              $sformatf("xtal, reenganche con el sistema ya arrancado: BOOT_HOLD solo de PLL_OK a listo (%0.1f ns)", hold_len));
                    check_led(4, "listo tras reenganchar");
                    check_invariants("perdida y reenganche");
                end

                if(scen == "turbo_marcha") begin
                    t_loss_ref = $realtime;
                    slot_period = 186.243;              // 5,369 MHz
                    if(SYNC != 0) begin
                        wait(!pll_ok);
                        t_lost = ($realtime - t_loss_ref) / 1000.0;
                        t_mute = (t_drive_fall - t_loss_ref) / 1000.0;
                        check(t_lost < 320.0,
                              $sformatf("sync, reloj del slot a 5,37 MHz: PLL_OK cae a los %0.2f us", t_lost));
                        check(t_mute > 0.0 && t_mute < 0.5,
                              $sformatf("sync, reloj del slot a 5,37 MHz: los pines se sueltan a los %0.3f us (LOCK bajo), sin esperar a PLL_OK", t_mute));
                        @(posedge clk27); @(posedge clk27); #1;
                        check(!drive_en && !boot_hold && !sys_reset_n,
                              "sync, reloj del slot fuera de rango: DRIVE_EN y BOOT_HOLD a 0, sistema en reset");
                        check_led(0, "reloj del slot fuera de rango");
                        wait_us(2_000.0);
                        check(!pll_ok && pll_reset,
                              "sync, reloj del slot a 5,37 MHz durante 2 ms: el rPLL sigue en reset (no se suelta con la entrada fuera de rango)");
                        slot_period = 279.365;
                        wait_ready(9_000.0, t_ready);
                        check(drive_en && sys_reset_n && relocked,
                              $sformatf("sync, el reloj del slot vuelve a 3,58 MHz: listo otra vez a los %0.3f ms y RELOCKED", t_ready / 1000.0));
                        check(hold_rises == 2 && hold_rise >= t_pllok && hold_len > 0.0 && hold_len < 2_000.0,
                              $sformatf("sync, reenganche sin que se parara el reloj del slot: BOOT_HOLD solo de PLL_OK a listo (%0.1f ns)", hold_len));
                        check_led(4, "listo tras reenganchar");
                    end
                    else begin
                        wait_us(2_000.0);
                        check(pll_ok && drive_en && sys_reset_n && pll_ok_rises == 1,
                              "xtal, reloj del slot a 5,37 MHz durante 2 ms: el rPLL (cristal) sigue enganchado y el sistema listo");
                        slot_period = 279.365;
                        check_led(5, "listo");
                    end
                    check_invariants("turbo en marcha");
                end
            end
        end

        $display("RESULTADO SYNC=%0d SCEN=%s: %0d pasan, %0d fallan", SYNC, scen, n_pass, n_fail);
        if(n_fail != 0) $display("BANCO: FALLA");
        else            $display("BANCO: PASA");
        $finish;
    end

    // tope de simulacion
    initial begin
        #200_000_000;
        $display("FALLA  tope de simulacion (200 ms)");
        $display("BANCO: FALLA");
        $finish;
    end

endmodule

`default_nettype wire
