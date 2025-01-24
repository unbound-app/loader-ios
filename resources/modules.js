Object.defineProperties(globalThis, {
	__d: {
		configurable: true,

		get() {
			globalThis.modules ??= globalThis.__c?.();


			return this.value;
		},

		set(v) {
			this.value = v;
		}
	}
});
