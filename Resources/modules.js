const window = this;

const { Object } = window;

const orig = Object.create;
Object.create = function (...args) {
	const [initializer] = args;
	const obj = orig.apply(this, args);

	if (initializer === null) {
		window.modules = obj;
		Object.create = orig;
	}

	return obj;
};

Object.freeze = (object) => object;