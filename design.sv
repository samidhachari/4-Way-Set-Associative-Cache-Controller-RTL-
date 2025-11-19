/* * Module: cache_controller_4way
 * Description: 4-Way Set Associative Cache with LRU and Write-Back Policy
 */

module cache_controller (
    input  logic        clk,
    input  logic        rst_n,

    // --- CPU Interface ---
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    input  logic        cpu_req,
    input  logic        cpu_write, // 1 = Write, 0 = Read
    output logic [31:0] cpu_rdata,
    output logic        cpu_ready, // High when transaction is done

    // --- Main Memory Interface (AXI-like) ---
    output logic [31:0] mem_addr,
    output logic [31:0] mem_wdata,
    output logic        mem_req,
    output logic        mem_write, // 1 = Write to Mem, 0 = Read from Mem
    input  logic [31:0] mem_rdata,
    input  logic        mem_ready  // Memory is done with operation
);

    // --- Parameters ---
    parameter NUM_SETS    = 16;  // Number of Sets
    parameter NUM_WAYS    = 4;   // 4-Way Associative
    parameter BLOCK_SIZE  = 1;   // 1 Word per block (Simplified for clarity)
    
    // Address Decoding: 32-bit Address
    // Offset: Ignored for 1-word block
    // Index:  4 bits (16 sets) -> bits [3:0]
    // Tag:    28 bits          -> bits [31:4]
    
    localparam INDEX_WIDTH = $clog2(NUM_SETS);
    localparam TAG_WIDTH   = 32 - INDEX_WIDTH;

    // --- Internal Signals ---
    logic [INDEX_WIDTH-1:0] index;
    logic [TAG_WIDTH-1:0]   tag;
    
    assign index = cpu_addr[INDEX_WIDTH-1:0];
    assign tag   = cpu_addr[31:INDEX_WIDTH];

    // --- Cache Arrays ---
    logic [31:0]        data_array  [NUM_SETS][NUM_WAYS];
    logic [TAG_WIDTH-1:0] tag_array [NUM_SETS][NUM_WAYS];
    logic               valid_bit   [NUM_SETS][NUM_WAYS];
    logic               dirty_bit   [NUM_SETS][NUM_WAYS];
    logic [1:0]         lru_counter [NUM_SETS][NUM_WAYS]; // 2-bit counter for Age

    // --- FSM States ---
    typedef enum logic [1:0] {IDLE, COMPARE, ALLOCATE, WRITEBACK} state_t;
    state_t state, next_state;

    // --- Variables for Logic ---
    logic hit;
    logic [1:0] hit_way;   // Which way hit?
    logic [1:0] victim_way; // Which way to replace?
    logic       victim_dirty;
    
    // --- Performance Counters ---
    integer hit_count;
    integer miss_count;

    // =================================================================
    // 1. Way Selection Logic (Comparator & LRU)
    // =================================================================
    always_comb begin
        hit = 0;
        hit_way = 0;
        victim_way = 0;
        
        // Check for Hit
        for (int i = 0; i < NUM_WAYS; i++) begin
            if (valid_bit[index][i] && (tag_array[index][i] == tag)) begin
                hit = 1;
                hit_way = i[1:0];
            end
        end

        // Find Victim (LRU Policy: Way with lowest counter value is LRU)
        // In a real design, this would be a tree logic. Simplified here:
        // We look for Valid=0 first (empty slot), else lowest LRU counter.
        if (!hit) begin
            // Default victim
            victim_way = 0; 
            for (int i = 0; i < NUM_WAYS; i++) begin
                 if (!valid_bit[index][i]) begin
                     victim_way = i[1:0]; 
                     break;
                 end
                 // Simple comparison for demonstration (assumes 0 is oldest)
                 if (lru_counter[index][i] == 2'b00) victim_way = i[1:0];
            end
        end
        
        victim_dirty = dirty_bit[index][victim_way];
    end

    // =================================================================
    // 2. FSM Control Logic
    // =================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    always_comb begin
        next_state = state;
        cpu_ready  = 0;
        mem_req    = 0;
        mem_write  = 0;
        mem_addr   = 0;
        mem_wdata  = 0;

        case (state)
            IDLE: begin
                if (cpu_req) next_state = COMPARE;
            end

            COMPARE: begin
                if (hit) begin
                    cpu_ready = 1; // Done
                    next_state = IDLE;
                end else begin
                    // MISS
                    if (valid_bit[index][victim_way] && victim_dirty) 
                        next_state = WRITEBACK;
                    else 
                        next_state = ALLOCATE;
                end
            end

            WRITEBACK: begin
                // Write Dirty line to Memory
                mem_req   = 1;
                mem_write = 1;
                mem_addr  = {tag_array[index][victim_way], index};
                mem_wdata = data_array[index][victim_way];
                
                if (mem_ready) next_state = ALLOCATE;
            end

            ALLOCATE: begin
                // Read new line from Memory
                mem_req   = 1;
                mem_write = 0;
                mem_addr  = cpu_addr; // Fetch requested address
                
                if (mem_ready) next_state = COMPARE; // Re-evaluate to hit
            end
        endcase
    end

    // =================================================================
    // 3. Data Path & Array Updates (Sequential)
    // =================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset Arrays
            for(int s=0; s<NUM_SETS; s++) 
                for(int w=0; w<NUM_WAYS; w++) begin
                    valid_bit[s][w] <= 0;
                    dirty_bit[s][w] <= 0;
                    lru_counter[s][w] <= 0;
                end
            hit_count <= 0;
            miss_count <= 0;
        end else begin
            
            case (state)
                COMPARE: begin
                    if (hit) begin
                        hit_count <= hit_count + 1;
                        
                        // LRU Update: Promote hit_way to max (3), decrement others
                        lru_counter[index][hit_way] <= 2'b11;
                        for (int i=0; i<NUM_WAYS; i++) begin
                            if (i != hit_way && lru_counter[index][i] > 0)
                                lru_counter[index][i] <= lru_counter[index][i] - 1;
                        end

                        // Read/Write Ops
                        if (cpu_write) begin
                            data_array[index][hit_way] <= cpu_wdata;
                            dirty_bit[index][hit_way]  <= 1;
                        end else begin
                            cpu_rdata <= data_array[index][hit_way];
                        end
                    end else begin
                        miss_count <= miss_count + 1;
                    end
                end

                ALLOCATE: begin
                    if (mem_ready) begin
                        // Fill Cache Line
                        data_array[index][victim_way] <= mem_rdata;
                        tag_array[index][victim_way]  <= tag;
                        valid_bit[index][victim_way]  <= 1;
                        dirty_bit[index][victim_way]  <= 0; // Clean
                        
                        // Reset LRU for this new line (Make it Most Recently Used)
                        lru_counter[index][victim_way] <= 2'b11;
                    end
                end
            endcase
        end
    end

endmodule