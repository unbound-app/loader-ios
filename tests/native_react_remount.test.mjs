import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runInNewContext } from 'node:vm';

const bridgeSource = readFileSync(new URL('../sources/NativePluginBridge.mm', import.meta.url), 'utf8');
const source = bridgeSource.match(/kReactRemountSource = R"REACT\(([\s\S]*?)\)REACT";/)?.[1];

assert.ok(source);

function createFixture() {
	const element = {};
	const props = {};
	const component = function Target() {};
	const root = { pendingLanes: 0, containerInfo: { containerTag: 31 } };
	const rootFiber = { tag: 3, stateNode: root, memoizedState: { element }, return: null };
	const parent = { tag: 5, return: rootFiber, lanes: 0, childLanes: 0 };
	const target = {
		tag: 0,
		key: null,
		index: 0,
		type: component,
		elementType: component,
		memoizedProps: props,
		return: parent,
	};
	const host = {
		tag: 5,
		stateNode: { canonical: { nativeTag: 42 } },
		return: target,
	};
	parent.child = target;
	root.current = rootFiber;
	const callbacks = [];
	const timers = [];
	const renderer = {
		render(receivedElement, tag, callback, _fourth, _fifth) {
			assert.equal(receivedElement, element);
			assert.equal(tag, 31);
			root.pendingLanes = 32;
			callbacks.push(callback);
		},
		createPortal() {},
		dispatchCommand() {},
		findHostInstance_DEPRECATED() {},
		findNodeHandle() {},
		getNodeFromInternalInstanceHandle() {},
		getPublicInstanceFromInternalInstanceHandle() {},
		getPublicInstanceFromRootTag() {},
		isChildPublicInstance() {},
		sendAccessibilityEvent() {},
		stopSurface() {},
		unmountComponentAtNode() {},
	};
	const manager = {
		findShadowNodeByTag_DEPRECATED(tag) {
			return tag === 42 ? {} : null;
		},
		findNodeAtPoint(_shadow, x, y, callback) {
			if (x === 10 && y === 20) callback(host);
		},
	};
	const context = {
		__r: () => renderer,
		nativeFabricUIManager: manager,
		setTimeout(callback) {
			timers.push(callback);
			return timers.length;
		},
		clearTimeout() {},
	};
	const bridge = runInNewContext(source, context);

	function commit() {
		const replacement = {
			tag: 0,
			key: null,
			index: 0,
			type: component,
			elementType: component,
		};
		parent.alternate = { child: replacement };
		root.current = {
			tag: 3,
			stateNode: root,
			memoizedState: { element },
		};
		root.pendingLanes = 0;
		callbacks.shift()?.();
		return replacement;
	}

	return { bridge, callbacks, commit, context, host, manager, parent, root, rootFiber, target, timers };
}

test('remounts only after scheduling the target parent and ancestor lanes', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	assert.equal(typeof identifier, 'number');
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	assert.equal(fixture.parent.lanes & 32, 32);
	assert.equal(fixture.rootFiber.childLanes & 32, 32);
	fixture.commit();
	await pending;
});

test('coalesces duplicate remount requests for one handle', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const first = fixture.bridge.remount(identifier, 42, 10, 20);
	const second = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(first, second);
	assert.equal(fixture.callbacks.length, 1);
	fixture.commit();
	await first;
});

test('rejects a stale handle when the component props change', () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	fixture.target.memoizedProps = {};
	assert.throws(
		() => fixture.bridge.remount(identifier, 42, 10, 20),
		{ code: 'NATIVE_REACT_STALE_FIBER' },
	);
});

test('rejects unsupported renderers without returning a Fiber handle', () => {
	const fixture = createFixture();
	fixture.context.__r = () => ({});
	assert.equal(fixture.bridge.supported(), false);
	assert.equal(fixture.bridge.lookup(42, 10, 20), null);
});

test('rejects renderer module errors and unexpected renderer exports', () => {
	const fixture = createFixture();
	fixture.context.__r = () => {
		throw new Error('missing module');
	};
	assert.equal(fixture.bridge.supported(), false);
	fixture.context.__r = () => ({ render() {} });
	assert.equal(fixture.bridge.lookup(42, 10, 20), null);
});

test('cancellation restores the Fiber before React commits', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	pending.cancel();
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
	assert.equal(fixture.target.key, null);
	assert.equal(fixture.parent.lanes, 0);
	assert.equal(fixture.rootFiber.childLanes ?? 0, 0);
	fixture.commit();
});

test('timeout restores the Fiber when React never commits', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.timers[0]();
	await assert.rejects(pending, { code: 'NATIVE_REACT_TIMEOUT' });
	assert.equal(fixture.target.key, null);
	assert.equal(fixture.parent.lanes, 0);
});

test('resolves a Fabric instance handle through the mounted alternate', () => {
	const fixture = createFixture();
	const alternateRoot = {
		tag: 3,
		stateNode: fixture.root,
		memoizedState: { element: fixture.rootFiber.memoizedState.element },
	};
	const alternateParent = { tag: 5, return: alternateRoot };
	const alternateTarget = {
		...fixture.target,
		return: alternateParent,
		alternate: fixture.target,
	};
	const alternateHost = {
		...fixture.host,
		return: alternateTarget,
		alternate: fixture.host,
	};
	fixture.host.alternate = alternateHost;
	fixture.root.current = alternateRoot;
	assert.equal(typeof fixture.bridge.lookup(42, 10, 20), 'number');
});
