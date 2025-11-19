# 4-Way Set Associative Cache Controller (RTL)

## Project Overview

This repository contains the Register Transfer Level (RTL) design and verification environment for a high-performance **4-Way Set Associative Cache Controller**. The project demonstrates expertise in computer architecture, complex Finite State Machine (FSM) design, and rigorous SystemVerilog verification methodologies.

The controller manages the data flow between a fast CPU interface and a slower Main Memory, implementing crucial memory hierarchy policies to minimize average memory access time.

---

## Key Features Implemented

* **Cache Structure:** Parameterized **4-Way Set Associative** architecture, allowing for easy configuration of cache size and block length.
* **Replacement Policy:** Implements the **LRU (Least Recently Used)** algorithm to determine cache line eviction, maximizing hit rates.
* **Write Policy:** Features a **Write-Back/Write-Allocate** policy, significantly reducing bus traffic by only writing modified (Dirty) data to memory when necessary.
* **Control Logic:** Developed a multi-state Mealy FSM to handle Hit, Clean Miss, and Dirty Eviction scenarios.
* **Verification:** Utilizes a class-based **SystemVerilog Testbench** with directed and self-checking mechanisms.
* **Performance Metrics:** Integrated cycle-accurate counters to measure and report **Hit Count, Miss Count, and Hit/Miss Cycles**.

---

## Architecture and Design Details

### 1. Cache Structure

The design uses a classic memory hierarchy address split:
$$\text{Address} = \{\text{Tag}, \text{Index}, \text{Offset}\}$$

The design employs four parallel memory banks (Ways) to facilitate the simultaneous lookup of tags within a single set.



### 2. Cache Controller FSM

The core of the design is the 4-state FSM, which manages the latency and data integrity during memory operations.

| State | Function | Key Action
| **IDLE** | Waiting for CPU Request | Monitors `cpu_req`.
| **COMPARE** | Checks all 4 tags in parallel | Determines Hit/Miss and Victim Status.
| **WRITEBACK** | Handles Dirty Eviction | Writes the old, modified line to Main Memory.
| **ALLOCATE** | Cache Fill | Fetches the new requested line from Main Memory.



### 3. LRU Implementation

The LRU logic for each set is handled by a set of usage counters (or age bits). Upon a hit or allocation, the corresponding way is promoted to "Most Recently Used" (highest counter value), and all other ways in that set are demoted. The line with the lowest counter is selected as the victim during a miss.

---

## Verification Methodology

The design was rigorously verified using SystemVerilog.

* **File:** `testbench.sv`
* **Behavioral Modeling:** The testbench includes a behavioral model for the **Main Memory**, which simulates configurable access **latency** (wait states) to stress-test the controller's stalling and handshake logic.
* **SVA (SystemVerilog Assertions):** Concurrent assertions were used to formally check properties like:
    * Data validity on CPU ready signal.
    * State transitions correctness (e.g., ensuring `WRITEBACK` always precedes `ALLOCATE` if the victim is dirty).
* **Test Cases:** The test suite covers all critical scenarios, including:
    * Compulsory Misses (First access).
    * Write Hits (Setting the Dirty bit).
    * Read Hits (Immediate data return).
    * Conflict Misses (Forcing LRU eviction and Write-Back).

---

## Setup and Simulation

This project can be simulated using any standard SystemVerilog simulator (e.g., Synopsys VCS, Mentor Graphics QuestaSim, or iverilog).

### File Structure
