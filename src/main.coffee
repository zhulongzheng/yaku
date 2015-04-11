

module.exports = class Promise

	###*
	 * This class follows the [Promises/A+](https://promisesaplus.com) and
	 * [ES6](http://people.mozilla.org/~jorendorff/es6-draft.html#sec-promise-objects) spec
	 * with some extra helpers.
	 * @param  {Function} executor Function object with two arguments resolve and reject.
	 * The first argument fulfills the promise, the second argument rejects it.
	 * We can call these functions, once our operation is completed.
	###
	constructor: (executor, _isRunImmediately) ->
		@_value = null
		@_handlers = []

		# "_isRunImmediately" is only used by then internally.
		run @, executor, _isRunImmediately

	###*
	 * Appends fulfillment and rejection handlers to the promise,
	 * and returns a new promise resolving to the return value of the called handler.
	 * @param  {Function} onFulfilled Optional. Called when the Promise is resolved.
	 * @param  {Function} onRejected  Optional. Called when the Promise is rejected.
	 * @return {Promise} It will return a new Promise which will resolve or reject after
	 * the current Promise.
	###
	then: (onFulfilled, onRejected) ->
		self = @

		new Promise (resolve, reject) ->
			addHandler self, onFulfilled, onRejected, resolve, reject
		, true

# ********************** Private **********************

	###
		'bind' and 'call' is slow, so we use Python
		style "self" with curry and closure.
		See: http://jsperf.com/call-vs-arguments
	###

	# These are some static symbolys.
	# The state value is designed to be 0, 1, 2. Not by chance.
	# See the genTrigger part's selector.
	$resolved = 0
	$rejected = 1
	$pending = 2

	_state: $pending
	_value: null

	# This is one of the most tricky part.
	#
	# For better performance, both memory and speed, the array is like below,
	# every 4 entities are paired together as a group:
	# ```
	#   0            1           2        3       ...
	# [ onFulfilled, onRejected, resolve, reject, ... ]
	# ```
	# To save memory the position of 0 and 1 may be replaced with their returned values,
	# then these values will be passed to 2 and 3.
	_handlers: []

	# It only counts when the current promise is on pending state.
	_thenCount: 0

	nextTick = do ->
		(fn) ->
			process.nextTick fn

	run = (self, executor, _isRunImmediately) ->
		if _isRunImmediately
			# For the Promise created by "then", we don't have to run the
			# executor after the next tick.
			executor genTrigger(self, $resolved),
				genTrigger(self, $rejected)
		else
			nextTick ->
				executor genTrigger(self, $resolved),
					genTrigger(self, $rejected)
		return

	# Push new handler to current promise.
	addHandler = (self, onFulfilled, onRejected, resolve, reject) ->
		offset = self._thenCount * 4

		switch self._state
			when $pending
				self._handlers[offset] = onFulfilled
				self._handlers[offset + 1] = onRejected
				self._handlers[offset + 2] = resolve
				self._handlers[offset + 3] = reject
				self._thenCount++

			when $resolved
				chainHandler self._value, onFulfilled, resolve

			when $rejected
				chainHandler self._value, onRejected, reject
		return

	# Chain value to a handler, then handler may be a promise or a function.
	chainHandler = (value, onFulfilled, onRejected) ->
		if value and typeof value.then == 'function'
			value.then onFulfilled, onRejected
		else
			onFulfilled value
		return

	# It will produce a trigger function to user.
	# Such as the resolve and reject in this `new Promise (resolve, reject) ->`.
	genTrigger = (self, state) -> (value) ->
		return if self._state != $pending

		self._state = state
		self._value = value

		i = 0
		len = self._thenCount * 4

		while i < len
			# Trick: Reuse the value of state as the handler selector.
			# The "i + state" shows the math nature of promise.
			handler = self._handlers[i + state]

			# TODO: Decide when to use reject of chained promise.
			thenHandler = self._handlers[i + 2]

			out = if handler then handler value else value

			if thenHandler
				chainHandler out, thenHandler
			else
				self._handlers[i] = out

			i += 4

		return
