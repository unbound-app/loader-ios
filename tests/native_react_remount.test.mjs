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
	const parentProps = {};
	const component = function Target() {};
	const viewComponent = function View() {};
	const animatedViewComponent = { displayName: 'AnimatedComponent(View)' };
	const root = { pendingLanes: 0, containerInfo: { containerTag: 31 } };
	const rootFiber = { tag: 3, stateNode: root, memoizedState: { element }, return: null };
	const parent = { tag: 5, return: rootFiber, lanes: 0, childLanes: 0, pendingProps: parentProps, memoizedProps: parentProps };
	const target = {
		tag: 0,
		key: null,
		index: 0,
		type: component,
		elementType: component,
		memoizedProps: props,
		pendingProps: props,
		return: parent,
	};
	const host = {
		tag: 5,
		stateNode: { canonical: { nativeTag: 42 } },
		return: target,
	};
	let activeHost = host;
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
			return tag === 42 && activeHost ? {} : null;
		},
		findNodeAtPoint(_shadow, x, y, callback) {
			if (x === 10 && y === 20) callback(activeHost);
		},
	};
	const context = {
		__r: () => renderer,
		ReactNative: { View: viewComponent, Animated: { View: animatedViewComponent } },
		nativeFabricUIManager: manager,
		setTimeout(callback) {
			timers.push(callback);
			return timers.length;
		},
		clearTimeout() {},
	};
	const bridge = runInNewContext(source, context);

	function commit({ reusedProps = false, detachedParent = false, removedTag = false } = {}) {
		if (reusedProps) target.pendingProps = {};
		const remountRequested = typeof target.key === 'string' && target.key.startsWith('__native_remount_');
		const replacement = {
			tag: 0,
			key: null,
			index: 0,
			type: target.type,
			elementType: target.elementType,
			memoizedProps: reusedProps ? {} : props,
			pendingProps: reusedProps ? {} : props,
		};
		const currentRoot = {
			tag: 3,
			stateNode: root,
			memoizedState: { element },
		};
		const currentParent = {
			tag: 5,
			return: detachedParent ? {} : currentRoot,
			memoizedProps: parent.memoizedProps,
			pendingProps: parent.pendingProps,
			child: replacement,
		};
		replacement.return = currentParent;
		parent.alternate = currentParent;
		root.current = currentRoot;
		activeHost = removedTag
			? null
			: { tag: 5, stateNode: { canonical: { nativeTag: 42 } }, return: replacement };
		root.pendingLanes = 0;
		callbacks.shift()?.();
		return { replacement, remountRequested };
	}

	return { animatedViewComponent, bridge, callbacks, commit, context, host, manager, parent, root, rootFiber, target, timers, viewComponent };
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
	assert.equal(fixture.target.key, null);
});

test('skips native component wrappers when selecting the remount target', async () => {
	const fixture = createFixture();
	const view = { tag: 0, elementType: fixture.viewComponent, return: fixture.target };
	const animated = { tag: 1, elementType: fixture.animatedViewComponent, return: view };
	fixture.host.return = {
		tag: 11,
		elementType: fixture.viewComponent,
		return: animated,
	};
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	fixture.commit();
	await pending;
});

test('does not skip a plugin component sharing a native wrapper name', async () => {
	const fixture = createFixture();
	fixture.target.elementType = function View() {};
	const identifier = fixture.bridge.lookup(42, 10, 20);
	assert.equal(typeof identifier, 'number');
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
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

test('rejects a remount if the view is reused with different props before commit', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	const result = fixture.commit({ reusedProps: true });
	assert.equal(result.remountRequested, false);
	await assert.rejects(pending, { code: 'NATIVE_REACT_STALE_FIBER' });
});

test('does not mark an alternate Fiber whose pending props changed', async () => {
	const fixture = createFixture();
	const alternate = {
		...fixture.target,
		alternate: fixture.target,
	};
	fixture.target.alternate = alternate;
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	alternate.pendingProps = {};
	assert.equal(alternate.key, null);
	pending.cancel();
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
});

test('rejects a remount if the parent is detached before commit', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.commit({ detachedParent: true });
	await assert.rejects(pending, { code: 'NATIVE_REACT_STALE_FIBER' });
});

test('accepts a remount when the replaced view tag has been removed', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.commit({ removedTag: true });
	await pending;
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

test('declines a target beneath an interruptible boundary before mutation', () => {
	for (const tag of [13, 19, 22]) {
		const fixture = createFixture();
		fixture.parent.return = { tag, return: fixture.rootFiber };
		assert.equal(fixture.bridge.lookup(42, 10, 20), null);
		assert.equal(fixture.target.key, null);
	}
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

test('cancellation after React consumes the key waits for commit cleanup', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	pending.cancel();
	assert.equal(typeof Object.getOwnPropertyDescriptor(fixture.target, 'key')?.get, 'function');
	fixture.commit();
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
	assert.equal(fixture.target.key, null);
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
