/// Bounded MPMC queue with tokens
ConcurrentQueue :: struct($T : Type, $policy : #type $P / ConcurrentQueuePolicy = ConcurrentQueuePolicy(capacity_per_subqueue = 1024)) {
    subqueues : []SubQueue(T, count = policy.capacity_per_subqueue);
}

ConcurrentQueuePolicy :: struct(
    capacity_per_subqueue: s64
) {}

ProducerToken :: struct(Queue : Type, attributes : TokenAttributes) #modify { return is_concurrent_queue(Queue); } {
    syncing, queuing :: #run attributes.syncing, #run attributes.queuing;

    #if #complete queuing == {
        case .exclusive; subqueue       : *SubQueue(Queue.T, Queue.policy.capacity_per_subqueue);
        case .broadwide; subqueue_index : s64;
    }
}

ConsumerToken :: struct(Queue : Type, attributes : TokenAttributes) #modify { return is_concurrent_queue(Queue); } {
    syncing, queuing :: #run attributes.syncing, #run attributes.queuing;

    #if #complete queuing == {
        case .exclusive; subqueue       : *SubQueue(Queue.T, Queue.policy.capacity_per_subqueue);
        case .broadwide; subqueue_index : s64;
    }
}

TokenAttributes :: struct {
    /// Specifies synchronization mode of the token operation such that it's made by user or by the queue itself.
    syncing : enum { external; internal; disabled :: external; enabled :: internal; };

    /// Specifies range of the token operation whenever it's working with a single sub-queue (exclusive) or with the complete sub-queue range (broadwide).
    queuing : enum { exclusive; broadwide; };
}

create_queue :: (queue : *ConcurrentQueue, number_of_subqueues : s64) {
    Basic.array_resize(*queue.subqueues, number_of_subqueues);
}

destroy_queue :: (queue : *ConcurrentQueue) {
    Basic.array_free(queue.subqueues);
}

acquire_producer_token :: (queue : *ConcurrentQueue, subqueue_index : s64, $attributes : TokenAttributes) -> ProducerToken(type_of(queue.*), attributes) {
    return acquire_producer_token(queue, subqueue_index, ProducerToken(type_of(queue.*), attributes));
}

acquire_producer_token :: (queue : *ConcurrentQueue, subqueue_index : s64, $token_type : Type) -> $ProducerTokenType #modify { ProducerTokenType = token_type; return is_producer_token(ProducerTokenType); } {
    #if #complete ProducerTokenType.queuing == {
        case .exclusive; return ProducerTokenType.{ subqueue       = *queue.subqueues[subqueue_index] };
        case .broadwide; return ProducerTokenType.{ subqueue_index = subqueue_index };
    }
}

release_producer_token :: (queue : *ConcurrentQueue, token : ProducerToken) {
    // @Todo
}

acquire_consumer_token :: (queue : *ConcurrentQueue, subqueue_index: s64, $attributes : TokenAttributes) -> ConsumerToken(type_of(queue.*), attributes) #no_context {
    return acquire_consumer_token(queue, subqueue_index, ConsumerToken(type_of(queue.*), attributes));
}

acquire_consumer_token :: (queue : *ConcurrentQueue, subqueue_index: s64, $token_type : Type) -> $ConsumerTokenType #modify { ConsumerTokenType = token_type; return is_consumer_token(ConsumerTokenType); } #no_context  {
    #if #complete ConsumerTokenType.queuing == {
        case .exclusive; return ConsumerTokenType.{ subqueue       = *queue.subqueues[subqueue_index] };
        case .broadwide; return ConsumerTokenType.{ subqueue_index = subqueue_index };
    }
}

release_consumer_token :: (queue : *ConcurrentQueue, token : ConsumerToken) {
    // @Todo
}

try_enqueue :: (queue : *ConcurrentQueue, token : ProducerToken, item: queue.T) -> bool #no_context {
    #if #complete token.queuing == {
        case .exclusive;
            return subqueue_try_enqueue_singular(token.subqueue, type_of(token), item);

        case .broadwide;
            subqueue_count := queue.subqueues.count;
            subqueue_index := token.subqueue_index;

            for ix : 0..queue.subqueues.count - 1 {
                subqueue := *queue.subqueues[(ix + subqueue_index) % subqueue_count];
                if subqueue_try_enqueue_singular(subqueue, type_of(token), item) {
                    return true;
                }
            }
            return false;
    }
}

try_dequeue :: (queue : *ConcurrentQueue, token : ConsumerToken, item: *queue.T) -> bool #no_aoc #no_context {
    #if #complete token.queuing == {
        case .exclusive;
            return subqueue_try_dequeue_singular(token.subqueue, type_of(token), item);

        case .broadwide;
            subqueue_count := queue.subqueues.count;
            subqueue_index := token.subqueue_index;

            for ix : 0..queue.subqueues.count - 1 {
                subqueue := *queue.subqueues[(ix + subqueue_index) % subqueue_count];
                if subqueue_try_dequeue_singular(subqueue, type_of(token), item) {
                    return true;
                }
            }
            return false;
    }
}

number_of_pending_items :: inline (queue: *ConcurrentQueue) -> s64 {
    total := 0;
    for subqueue: queue.subqueues {
        total += subqueue.write - subqueue.read;
    }
    return total;
}

#scope_file

is_concurrent_queue :: (T : Type) -> bool #compile_time {
    DummyConcurrentQueue :: ConcurrentQueue(int, ConcurrentQueuePolicy(2));
    ti := cast(*Type_Info_Struct) T;
    return ti.polymorph_source_struct == type_info(DummyConcurrentQueue).polymorph_source_struct;
}

is_producer_token :: (T : Type) -> bool #compile_time {
    DummyConcurrentQueue :: ConcurrentQueue(int, ConcurrentQueuePolicy(2));
    DummyProducerToken   :: ProducerToken(DummyConcurrentQueue, .{});
    ti := cast(*Type_Info_Struct) T;
    return ti.polymorph_source_struct == type_info(DummyProducerToken).polymorph_source_struct;
}

is_consumer_token :: (T : Type) -> bool #compile_time {
    DummyConcurrentQueue :: ConcurrentQueue(int, ConcurrentQueuePolicy(2));
    DummyConsumerToken   :: ConsumerToken(DummyConcurrentQueue, .{});
    ti := cast(*Type_Info_Struct) T;
    return ti.polymorph_source_struct == type_info(DummyConsumerToken).polymorph_source_struct;
}

/// Internal heterogenous sub-queue. Might act as SPMC or MPMC queue.
/**
 *  @Todo: doc [SPMC / MPMC]
 */
SubQueue :: struct($T : Type, $count : s64) {
    #assert is_power_of_2(count);
    index_mask :: count - 1;

    consumed : s64;
    reserved : s64;
    commited : s64;

    items : [count]T = ---;
}

subqueue_try_enqueue_singular :: (queue : *SubQueue, $TokenType : Type, item : queue.T) -> bool #modify { return is_producer_token(TokenType); } #no_context {
    #if #complete TokenType.syncing == {
        case .external; return subqueue_try_enqueue_singular_with_disabled_sync(queue, item);
        case .internal; return subqueue_try_enqueue_singular_with_enabled_sync(queue, item);
    }
}

subqueue_try_enqueue_singular_with_disabled_sync :: (queue : *SubQueue, item : queue.T) -> bool #no_context {
    capacity   :: queue.count;
    index_mask :: queue.index_mask;

    consumed := load(*queue.consumed, memory_order = .relaxed);
    reserved := load(*queue.reserved, memory_order = .relaxed);
    commited := load(*queue.commited, memory_order = .relaxed);

    if commited - reserved == capacity {
        return false;
    }

    store(*queue.reserved, reserved + 1, memory_order = .release); // @Todo: direct increment?
    queue.items[commited & index_mask] = item;
    store(*queue.commited, reserved + 1, memory_order = .release); // @Todo: direct increment?

    return true;
}

/// Performs enqueue to the sub-queue with internal synchronization.
/**
 *  This cannot be used in pair with 'subqueue_try_enqueue_singular_with_disabled_sync' over the same sub-queue.
 */
subqueue_try_enqueue_singular_with_enabled_sync :: (queue : *SubQueue, item : queue.T) -> bool #no_context {
    capacity   :: queue.count;
    index_mask :: queue.index_mask;

    // @Todo: make text more readable
    //
    // Here we are doing a double indexing that this enables us to safely write data in the queue and notify others about it.
    //
    // In the first step we reserve a slot from the arena such that only one thread would be able to queuing it.
    //
    // After that we write the item in the arena by obtained index. Even if data is pushed in the queue, it's impossible
    // to dequeue it right now, because the second write index (commited) is not updated yet.
    //
    // So, the third stage would be an attempt to write 'reserved + 1' in the 'commited' index.
    // We repeat it until success. Finishing this is a true notification that we did a successful insert.
    // It's important to use 'reserved' value as a source, because all the writes must appear in the strong order.
    // Updating 'commited' by its value would not guarantee this.

    reserved := load(*queue.reserved, memory_order = .acquire);
    consumed := load(*queue.consumed, memory_order = .acquire);

    while reserving := true {
        if reserved - consumed >= capacity {
            return false;
        }

        real_reserved := compare_and_swap(*queue.reserved, reserved, reserved + 1, memory_order = .release);
        if real_reserved != reserved {
            reserved = real_reserved;
            consumed = load(*queue.consumed, memory_order = .relaxed);
            continue reserving;
        }

        break reserving;
    }

    queue.items[reserved & index_mask] = item;

    while compare_and_swap(*queue.commited, reserved, reserved + 1, memory_order = .release) != reserved {
        continue;
    }

    return true;
}

subqueue_try_dequeue_singular :: (queue : *SubQueue, $TokenType : Type, item : *queue.T) -> bool #modify { return is_consumer_token(TokenType); } #no_context  {
    #if #complete TokenType.syncing == {
        case .external; return subqueue_try_dequeue_singular_with_external_sync(queue, item);
        case .internal; return subqueue_try_dequeue_singular_with_internal_sync(queue, item);
    }
}

subqueue_try_dequeue_singular_with_external_sync :: (queue : *SubQueue, item : *queue.T) -> bool #no_aoc #no_context {
    capacity   :: queue.count;
    index_mask :: queue.index_mask;

    consumed := load(*queue.consumed, memory_order = .relaxed);
    commited := load(*queue.consumed, memory_order = .relaxed);

    if commited - consumed == 0 {
        return false;
    }

    item.* = queue.items[consumed & index_mask];
    store(*queue.consumed, consumed + 1, memory_order = .release); // @Todo: direct increment?

    return true;
}

subqueue_try_dequeue_singular_with_internal_sync :: (queue : *SubQueue, item : *queue.T) -> bool #no_aoc #no_context {
    capacity   :: queue.count;
    index_mask :: queue.index_mask;

    // This one is a bit tricky, as we should remember, that readings do no harm.
    // Thus, we can do an actual read just before an attempt to confirm the read.
    // Even if read operation is concurrent itself, only 'consumed' index update should be synchronized.

    consumed := load(*queue.consumed, memory_order = .acquire);
    commited := load(*queue.commited, memory_order = .acquire);

    while consuming := true {
        if commited - consumed <= 0 {
            return false;
        }

        item.* = queue.items[consumed & index_mask];

        real_consumed := compare_and_swap(*queue.consumed, consumed, consumed + 1, memory_order = .release);
        if real_consumed != consumed {
            consumed = real_consumed;
            commited = load(*queue.commited, memory_order = .relaxed);
            continue consuming;
        }

        break consuming;
    }

    return true;
}

is_power_of_2 :: inline (value: $T) -> bool {
    return value > 0 && value & (value - 1) == 0;
}

next_power_of_2 :: inline (value: $T) -> T {
    v := value;

    v -= 1;
    #if size_of(T) >= 1 {
        v |= v >> 1;
        v |= v >> 2;
        v |= v >> 4;
    }
    #if size_of(T) >= 2 {
        v |= v >> 8;
    }
    #if size_of(T) >= 4 {
        v |= v >> 16;
    }
    #if size_of(T) >= 8 {
        v |= v >> 32;
    }
    v += 1;

    return v;
}

Basic :: #import "Basic";

#import "core/atomic";
