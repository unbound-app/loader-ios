import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runInNewContext } from 'node:vm';

const bridgeSource = readFileSync(new URL('../sources/NativePluginBridge.mm', import.meta.url), 'utf8');
const source = bridgeSource.match(/kReactRemountSource = R"REACT\(([\s\S]*?)\)REACT";/)?.[1];

assert.ok(source);

function createFixture(options = {}) {
	const element = {};
	const props = {};
	const parentProps = {};
	const component = function Target() {};
	const viewComponent = function View() {};
	const animatedViewComponent = { displayName: 'AnimatedComponent(View)' };
	const root = { tag: 1, pendingLanes: 0, containerInfo: { containerTag: 31 } };
	const rootFiber = { tag: 3, mode: 1, stateNode: root, memoizedState: { element }, return: null };
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
	const commits = [];
	const observations = [];
	const renderOptions = {};
	let nextLane = 1024;
	const renderer = {
		render(receivedElement, tag, callback, _fourth, _fifth) {
			assert.equal(receivedElement, element);
			assert.equal(tag, 31);
			root.pendingLanes |= options.invalidTransitionLane ? 3 : nextLane;
			nextLane <<= 1;
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
		React: { startTransition(callback) { callback(); } },
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
		observations.push({
			remountRequested,
			alternateKey: target.alternate?.key,
			parentLanes: parent.lanes,
			rootChildLanes: rootFiber.childLanes,
			rootTag: root.tag,
			rootMode: root.current.mode,
		});
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
			mode: root.current.mode,
			stateNode: root,
			memoizedState: { element },
			alternate: root.current,
		};
		root.current.alternate = currentRoot;
		const currentParent = {
			tag: 5,
			return: detachedParent ? {} : currentRoot,
			memoizedProps: parent.memoizedProps,
			pendingProps: parent.pendingProps,
			child: remountRequested ? replacement : target,
		};
		currentParent.child.return = currentParent;
		parent.alternate = currentParent;
		root.current = currentRoot;
		activeHost = removedTag
			? null
			: remountRequested
				? { tag: 5, stateNode: { canonical: { nativeTag: 42 } }, return: replacement }
				: host;
		root.pendingLanes = 0;
		for (const callback of callbacks.splice(0)) callback();
		const result = { replacement, remountRequested };
		commits.push(result);
		return result;
	}

	return { animatedViewComponent, bridge, callbacks, commit, commits, context, host, manager, observations, parent, renderOptions, root, rootFiber, target, timers, viewComponent };
}

test('remounts only after scheduling the target parent and ancestor lanes', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	assert.equal(typeof identifier, 'number');
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commits.length, 0);
	assert.match(fixture.target.key, /^__native_remount_/);
	assert.equal(fixture.parent.lanes & 1024, 1024);
	assert.equal(fixture.rootFiber.childLanes & 1024, 1024);
	fixture.commit();
	await pending;
	assert.equal(fixture.target.key, null);
	assert.equal(fixture.parent.lanes, 0);
	assert.equal(fixture.rootFiber.childLanes, undefined);
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
	assert.equal(fixture.commit().remountRequested, true);
	await pending;
});

test('does not skip a plugin component sharing a native wrapper name', async () => {
	const fixture = createFixture();
	fixture.target.elementType = function View() {};
	const identifier = fixture.bridge.lookup(42, 10, 20);
	assert.equal(typeof identifier, 'number');
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commit().remountRequested, true);
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

test('keeps separate Fiber scopes independent during a remount', async () => {
	const fixture = createFixture();
	const firstIdentifier = fixture.bridge.lookup(42, 10, 20);
	const secondIdentifier = fixture.bridge.lookup(42, 10, 20);
	assert.notEqual(firstIdentifier, secondIdentifier);
	const first = fixture.bridge.remount(firstIdentifier, 42, 10, 20);
	assert.equal(fixture.bridge.shared(secondIdentifier), null);
	assert.throws(() => fixture.bridge.remount(secondIdentifier, 42, 10, 20), {
		code: 'NATIVE_REACT_BUSY',
	});
	assert.equal(fixture.callbacks.length, 1);
	fixture.commit();
	await first;
});

test('commits an isolated remount after a transition is scheduled', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commits.length, 0);
	assert.equal(fixture.root.pendingLanes, 1024);
	assert.equal(fixture.root.tag, 1);
	assert.equal(fixture.root.current.mode, 1);
	assert.equal(fixture.commit().remountRequested, true);
	await pending;
});

test('rejects a remount if the view is reused with different props before commit', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	fixture.renderOptions.reusedProps = true;
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commit(fixture.renderOptions).remountRequested, false);
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
	alternate.pendingProps = {};
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commit().remountRequested, true);
	assert.equal(fixture.observations[0].alternateKey, null);
	assert.equal(alternate.key, null);
	await pending;
});

test('rejects a remount if the parent is detached before commit', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	fixture.renderOptions.detachedParent = true;
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.commit(fixture.renderOptions);
	await assert.rejects(pending, { code: 'NATIVE_REACT_STALE_FIBER' });
});

test('accepts a remount when the replaced view tag has been removed', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	fixture.renderOptions.removedTag = true;
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.commit(fixture.renderOptions);
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
		fixture.parent.return = { tag, memoizedState: {}, return: fixture.rootFiber };
		assert.equal(fixture.bridge.lookup(42, 10, 20), null);
		assert.equal(fixture.target.key, null);
	}
});

test('accepts settled Suspense and visible Offscreen ancestors', async () => {
	for (const tag of [13, 22]) {
		const fixture = createFixture();
		fixture.parent.return = { tag, memoizedState: null, return: fixture.rootFiber };
		const identifier = fixture.bridge.lookup(42, 10, 20);
		assert.equal(typeof identifier, 'number');
		const pending = fixture.bridge.remount(identifier, 42, 10, 20);
		assert.equal(fixture.commit().remountRequested, true);
		await pending;
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

test('cancellation after a committed remount does not report an abort', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.equal(fixture.commit().remountRequested, true);
	pending.cancel();
	await pending;
	assert.equal(fixture.target.key, null);
});

test('release before the key is consumed cancels without a remount', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.bridge.release(identifier);
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
	assert.equal(fixture.commit().remountRequested, false);
});

test('cancels a pending remount without releasing the Fiber handle', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	fixture.bridge.cancel(identifier);
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
	assert.equal(fixture.commit().remountRequested, false);
	const retry = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	fixture.bridge.cancel(identifier);
	assert.equal(fixture.commit().remountRequested, false);
	await assert.rejects(retry, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
});

test('release after the key is consumed aborts the pending transition', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	fixture.bridge.release(identifier);
	assert.equal(fixture.callbacks.length, 2);
	assert.equal(fixture.commit().remountRequested, false);
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
});

test('cancellation watchdog settles when the overriding transition never commits', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	fixture.bridge.release(identifier);
	assert.equal(fixture.timers.length, 2);
	fixture.timers[1]();
	await assert.rejects(pending, { code: 'NATIVE_PLUGIN_SCOPE_DISPOSED' });
	assert.equal(fixture.target.key, null);
});

test('release invalidates a Fiber handle before it can remount', () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	fixture.bridge.release(identifier);
	assert.throws(() => fixture.bridge.remount(identifier, 42, 10, 20), {
		code: 'NATIVE_REACT_STALE_FIBER',
	});
	assert.equal(fixture.target.key, null);
});

test('timeout aborts a transition after React consumes the key', async () => {
	const fixture = createFixture();
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	assert.match(fixture.target.key, /^__native_remount_/);
	fixture.timers[0]();
	assert.equal(fixture.commit().remountRequested, false);
	await assert.rejects(pending, { code: 'NATIVE_REACT_TIMEOUT' });
	assert.equal(fixture.target.key, null);
	assert.equal(fixture.parent.lanes, 0);
});

test('rejects a transition without a single isolated lane', async () => {
	const fixture = createFixture({ invalidTransitionLane: true });
	const identifier = fixture.bridge.lookup(42, 10, 20);
	const pending = fixture.bridge.remount(identifier, 42, 10, 20);
	await assert.rejects(pending, { code: 'NATIVE_REACT_UNSUPPORTED_RENDERER' });
	assert.equal(fixture.target.key, null);
	assert.equal(fixture.parent.lanes, 0);
	assert.equal(fixture.commit().remountRequested, false);
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
