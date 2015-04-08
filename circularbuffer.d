module std.experimental.circularbuffer;

import std.range;

public struct CircularBuffer(T)
{
	static assert(isInputRange!(CircularBuffer!T));
	static assert(isOutputRange!(CircularBuffer!T, T));
	static assert(isForwardRange!(CircularBuffer!T));
	static assert(hasLength!(CircularBuffer!T));

	private T[]	items;
	private size_t first, last;

	invariant {
		assert(first < items.length || this == this.init);
		assert(last < items.length || this == this.init);
	}

	public @property nothrow T[] toArray() 
	out (result) {
		assert(result.length == this.length);
	}
	body {
		if (first <= last)
			return items[first..last];
		else
			return items[first..$] ~ items[0..last];
	}

	public @property nothrow const size_t length() {
		return last >= first ? last - first : last - first + items.length;
	}

	private enum delta = 8;

	private @property nothrow const bool full() { 
		return this.length + 1 >= items.length; 
	}

	private void resize() {
		immutable count = this.length;
		auto newp = new T[count + delta];
		if (newp.capacity)
			newp.length = newp.capacity;
		if (first <= last) {
			newp[0..count] = items[first..last];
		}
		else {
			newp[0..items.length - first] = items[first..$];
			newp[items.length - first..count] = items[0..last];
		}
		first = 0;
		last = count;
		items = newp;
		assert(!full);
	}

	// Input range:

	public @property const nothrow bool empty() { return first == last; }

	public @property const ref front() {
		assert(!empty);
		return items[first]; 
	}

	public @property T popFront() {
		assert(!empty);
		auto ret = items[first++];
		if (first == items.length)
			first = 0;
		return ret;
	}

	// Output range:

	public void put(T p) 
	out {
		assert(!empty);
	}
	body {
		if (full)
			resize();
		items[last] = p;
		if (++last == items.length)
			last = 0;
	}

	// Forward range:

	public @property nothrow typeof(this) save() {
		return this;
	}
}

unittest
{
	CircularBuffer!int cb;
	assert(cb.empty);
	assert(cb.full);
	assert(cb.toArray == []);
	cb.put(1);
	assert(cb.toArray == [1]);
	assert(!cb.empty);
	assert(cb.front == 1);
	assert(!cb.empty);
	auto s = cb.save;
	assert(s.items is cb.items);
	assert(cb.popFront == 1);
	assert(cb.toArray == []);
	assert(cb.empty);
	assert(!cb.full);
	assert(!s.empty);
	assert(s.popFront == 1);
	assert(s.empty);
}

static assert(isInputRange!(CircularBuffer!int));
static assert(isOutputRange!(CircularBuffer!int, int));
static assert(isForwardRange!(CircularBuffer!int));
static assert(hasLength!(CircularBuffer!int));
