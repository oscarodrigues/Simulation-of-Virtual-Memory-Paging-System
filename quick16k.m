clc
clear all
close all

%Inputted Data (RW Signals and Addresses)
[MAT_RW,MAT_Address] = readvars('quick16k.txt');
[matrows,matcols] = size(MAT_Address);
membitwidth = 14;
virtbitwidth = 16;

%Specifications
for pagebitwidth = 4:(membitwidth-4) %Ranges from 4 to membitwidth-4
    for tagbitwidth = 1:(virtbitwidth-pagebitwidth) %Ranges 1 to virtbitwidth-pagebitwidth
        
        %TLB Array Initialization
        tlbarray_valid = zeros((2^tagbitwidth),1);
        tlbarray_tag = zeros((2^tagbitwidth),1);
        tlbarray_frequency = zeros((2^tagbitwidth),1);
        tlbarray_dirty = zeros((2^tagbitwidth),1);

        %Page Table Array Initialization
        ptearray_valid = zeros((2^(virtbitwidth-pagebitwidth)),1);
        ptearray_tlbfield = zeros((2^(virtbitwidth-pagebitwidth)),1);
        ptearray_dirty = zeros((2^(virtbitwidth-pagebitwidth)),1);
        ptearray_memfield = zeros((2^(virtbitwidth-pagebitwidth)),1);
        ptearray_memfield(:,:) = -1;

        %Memory Array Initialization
        memarray_valid = zeros((2^(membitwidth-pagebitwidth)),1);
        memarray_frequency = zeros((2^(membitwidth-pagebitwidth)),1);
        memarray_tlbfield = zeros((2^(membitwidth-pagebitwidth)),1);
        memarray_ptefield = zeros((2^(membitwidth-pagebitwidth)),1);

        %If pagebits>membits, or pagebits>virtbits, or tlbbits>membits
        if ((pagebitwidth > membitwidth) || (pagebitwidth > virtbitwidth) || (tagbitwidth > membitwidth))
            fprintf('Error in bit sizes. Please make sure the program is configured correctly.');
            return
        end

        %Performance Calcualtion
        tlbhit = 0;
        tlbmiss = 0;
        memhit = 0;
        memmiss = 0;
        writeback = 0;

        %Program
        for a = 1:matrows

            %Bit Parsing
            tagbits = floor(bitsra(MAT_Address(a),pagebitwidth))+1;

            %Virtual Memory Paging System
            found = 0;
            for b = 1:(2^tagbitwidth)
                if (tlbarray_valid(b,1) == 1)%If valid flag is TRUE:
                    if (tlbarray_tag(b,1) == tagbits -1) %If the tag is correct:
                        %Hit
                        tlbarray_frequency(b,1) = a; %Adjust frequency
                        if (cell2mat(MAT_RW(a)) == 'W') %If writing:
                            tlbarray_dirty(b,1) = 1; %Adjust dirty    
                        end
                        tlbhit = tlbhit + 1; %Increment TLB hit count
                        found = 1;
                        break
                    end
                end
            end
            if (found == 0)
            %Miss
                tlbmiss = tlbmiss + 1; %Increment TLB miss count
                %Find LRU
                [minval_tlb,minind_tlb] = min(tlbarray_frequency(:,1)); %Find minimum value and minimum index
                tlbtagfrommem1 = tlbarray_tag(minind_tlb,1)+1; %+1 to deal with indexing 
                ptearray_dirty(tlbtagfrommem1,1) = bitor(tlbarray_dirty(minind_tlb,1),ptearray_dirty(tlbtagfrommem1,1)); %Migration
                tlbreferencefrompte = ptearray_memfield(tagbits,1);
                if (ptearray_memfield(tagbits,1) >= 0) %If memory is mapped:
                    memhit = memhit + 1; %Increment memory hit count
                    memarray_frequency(tlbreferencefrompte,1) = a; %Adjust frequency
                else
                    memmiss = memmiss + 1; %Increment memory miss count
                    [minval_mem,minind_mem] = min(memarray_frequency(:,1)); %Find minimum value and minimum index
                    if (memarray_valid(minind_mem,1) == 1) %If valid flag is TRUE:
                        tlbreferencefrommem = memarray_tlbfield(minind_mem,1);
                        tlbtagfrommem2 = tlbarray_tag(tlbreferencefrommem,1)+1;
                        ptearray_dirty(tlbtagfrommem2,1) = bitor(tlbarray_dirty(tlbreferencefrommem,1),ptearray_dirty(tlbtagfrommem2,1)); %Migration
                        tlbarray_valid(tlbreferencefrommem,1) = 0; %Invalidate TLB entry that memory references
                        ptearray_memfield(tlbtagfrommem2,1) = -1; %Invalidate PTE field
                        if (ptearray_dirty(tlbtagfrommem2,1) == 1) %If PTE dirty bit is DIRTY:
                            ptearray_dirty(tlbtagfrommem2,1) = 0; %Adjust dirty
                            writeback = writeback + 1; %Increment writeback count
                        end
                    end
                    memarray_valid(minind_mem,1) = 1; %Adjust valid flag
                    memarray_frequency(minind_mem,1) = a; %Adjust frequency
                    memarray_tlbfield(minind_mem,1) = minind_tlb; %Adjust TLB field
                    memarray_ptefield(minind_mem,1) = tagbits - 1; %Adjust PTE field
                    ptearray_memfield(tagbits,1) = minind_mem; %Adjust PTE address
                end
                ptearray_tlbfield(tagbits,1) = minind_tlb; %Adjust PTE reference
                if (cell2mat(MAT_RW(a)) == 'W') %If writing:
                    tlbarray_dirty(minind_tlb,1) = 1; %Adjust dirty
                    ptearray_dirty(tagbits,1) = 1; %Adjust dirty
                else
                    tlbarray_dirty(minind_tlb,1) = 0; %Adjust dirty
                    ptearray_dirty(tagbits,1) = 0; %Adjust dirty
                end
                tlbarray_valid(minind_tlb,1) = 1; %Adjust valid flag
                tlbarray_tag(minind_tlb,1) = tagbits -1; %Adjust tagbits
                tlbarray_frequency(minind_tlb,1) = a; %Adjust frequency   
            end
        end

        %Flushing Out Dirty Lines
        for f = 1:(2^tagbitwidth)
            if (tlbarray_dirty(f,1) == 1) %If TLB dirty bit is DIRTY:
                if (tlbarray_valid(f,1) == 1)
                    writeback = writeback + 1; %Increment writeback count
                    tlbarray_dirty(f,1) = 0; %Adjust dirty
                    ptearray_dirty(tlbarray_tag(f,1)+1,1) = 0; %Adjust dirty
                end
            end
        end
        for g = 1:(2^(virtbitwidth-pagebitwidth)) %If PTE dirty bit is DIRTY:
            if (ptearray_dirty(g,1) == 1)
                writeback = writeback + 1; %Increment writeback count
                ptearray_dirty(g,1) = 0; %Adjust dirty
            end
        end

        %Performance Calcualtion
        hitrate = (tlbhit/(tlbhit + tlbmiss))*100;
        cost = ((2^tagbitwidth)*pagebitwidth);

        %Displaying Inputs and Outputs
        fprintf('For inputted values of tlbbits = %d, pagebits = %d, membits = %d, and virtbits = %d, ',tagbitwidth,pagebitwidth,membitwidth,virtbitwidth)
        fprintf('we get cost = %d, hitrate (percent) = %8.6f, TLB hits = %d, TLB misses = %d, memory hits = %d, memory misses = %d, and writebacks = %d. \n\n',cost,hitrate,tlbhit,tlbmiss,memhit,memmiss,writeback)
        
    end
end