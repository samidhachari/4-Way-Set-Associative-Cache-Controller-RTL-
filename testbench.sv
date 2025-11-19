module tb_cache;
    // Signals
    logic clk, rst_n;
    logic [31:0] cpu_addr, cpu_wdata, cpu_rdata;
    logic cpu_req, cpu_write, cpu_ready;
    
    logic [31:0] mem_addr, mem_wdata, mem_rdata;
    logic mem_req, mem_write, mem_ready;

    // Instantiate DUT
    cache_controller DUT (.*);

    // Fake Main Memory Storage
    logic [31:0] main_memory [1024]; 

    // Clock Generation
    always #5 clk = ~clk;

    // ============================================================
    // Task: CPU Write
    // ============================================================
    task cpu_write_task(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        cpu_req   = 1;
        cpu_write = 1;
        cpu_addr  = addr;
        cpu_wdata = data;
        
        wait(cpu_ready); // Wait for Cache to finish
        
        @(posedge clk);
        cpu_req   = 0;
        $display("[CPU WRITE] Addr: %h | Data: %h | Time: %t", addr, data, $time);
    endtask

    // ============================================================
    // Task: CPU Read
    // ============================================================
    task cpu_read_task(input [31:0] addr);
        @(posedge clk);
        cpu_req   = 1;
        cpu_write = 0;
        cpu_addr  = addr;
        
        wait(cpu_ready); // Wait for Cache to return data
        
        @(posedge clk);
        cpu_req   = 0;
        $display("[CPU READ ] Addr: %h | Data: %h | Time: %t", addr, cpu_rdata, $time);
    endtask

    // ============================================================
    // Main Memory Simulation (Responds with Latency)
    // ============================================================
    initial begin
        mem_ready = 0;
        forever begin
            @(posedge clk);
            if (mem_req) begin
                // Simulate Memory Access Latency (e.g., 4 cycles)
                repeat(4) @(posedge clk); 
                
                if (mem_write) begin
                    main_memory[mem_addr[9:0]] = mem_wdata;
                    $display("\t[MEM WRITE] Written to Main Memory: Addr %h", mem_addr);
                end else begin
                    mem_rdata = main_memory[mem_addr[9:0]];
                end
                
                mem_ready = 1;
                @(posedge clk);
                mem_ready = 0;
            end
        end
    end

    // ============================================================
    // Test Scenario
    // ============================================================
    initial begin
        // Initialize
        clk = 0; rst_n = 0;
        cpu_req = 0;
        
        // Initialize fake memory
        main_memory[10] = 32'hDEAD_BEEF;
        main_memory[20] = 32'hCAFE_BABE;

        // Reset
        #20 rst_n = 1; 

        $display("--- STARTING TEST ---");

        // 1. Compulsory Miss (Read from Mem)
        cpu_read_task(32'h0000_000A); // Should fetch DEAD_BEEF

        // 2. Cache Hit (Data already in cache)
        cpu_read_task(32'h0000_000A); // Should complete instantly

        // 3. Write Hit (Modify Data)
        cpu_write_task(32'h0000_000A, 32'h1111_2222);

        // 4. Read Back (Verify Update)
        cpu_read_task(32'h0000_000A); // Should read 1111_2222

        // 5. Conflict Miss (Fill all 4 ways to force eviction)
        // Assuming Set 0, we have Way 0 filled. Let's fill 3 more ways.
        cpu_write_task(32'h0000_100A, 32'hDATA_WAY1);
        cpu_write_task(32'h0000_200A, 32'hDATA_WAY2);
        cpu_write_task(32'h0000_300A, 32'hDATA_WAY3);
        
        // Now Set 0 is full. The next write should trigger EVICTION (Writeback)
        // because the LRU logic should pick the oldest line.
        cpu_write_task(32'h0000_400A, 32'hDATA_WAY4);

        #100;
        $display("--- FINISHED ---");
        $display("Total Hits: %0d", DUT.hit_count);
        $display("Total Misses: %0d", DUT.miss_count);
        $finish;
    end

    // ============================================================
    // Assertions
    // ============================================================
    // Check 1: If ready is high, data valid must be stable
    property p_valid_data;
        @(posedge clk) cpu_ready |-> !$isunknown(cpu_rdata);
    endproperty
    assert property(p_valid_data) else $error("CPU Data Unknown on Ready!");

endmodule