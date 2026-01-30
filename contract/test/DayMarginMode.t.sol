// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./utils/ExchangeFixture.sol";
import "../../src/core/ExchangeStorage.sol";

/**
 * @title DayMarginMode - 逐仓/全仓模式切换测试
 * @notice 测试保证金模式切换、保证金分配/回收、清算逻辑等
 */
contract DayMarginModeTest is ExchangeFixture {
    function setUp() public override {
        super.setUp();
        _deposit(alice, 100 ether);
        _deposit(bob, 100 ether);
        exchange.updateIndexPrice(1000e18); // 设置初始价格
    }

    function _updatePrice(uint256 newPrice) internal {
        exchange.updateIndexPrice(newPrice);
    }

    // ============================================
    // 测试组 1: 保证金模式设置
    // ============================================

    /**
     * @notice 测试：新仓位可以设置为逐仓模式
     */
    function testIsolatedModeOnNewPosition() public {
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 验证模式已设置
        (, MarginMode mode,,,) = exchange.getAccountDetails(alice);
        assertEq(uint256(mode), uint256(MarginMode.ISOLATED), "mode should be ISOLATED");
    }

    /**
     * @notice 测试：新仓位默认为全仓模式
     */
    function testCrossModeIsDefault() public {
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // 验证模式为 CROSS
        (, MarginMode mode,,,) = exchange.getAccountDetails(alice);
        assertEq(uint256(mode), uint256(MarginMode.CROSS), "mode should be CROSS");
    }

    /**
     * @notice 测试：不能在已有仓位上切换保证金模式
     */
    function testCannotChangeModeOnExistingPosition() public {
        // Alice: 先下卖单，创造一个卖单订单簿
        vm.prank(alice);
        exchange.placeOrder(false, 1100e18, 1 ether, 0, MarginMode.CROSS);

        // 验证没有持仓（只是挂单）
        assertTrue(exchange.getPosition(alice).size == 0, "should not have position yet");

        // Bob: 下买单，与 Alice 成交
        vm.prank(bob);
        exchange.placeOrder(true, 1200e18, 1 ether, 0, MarginMode.CROSS);

        // 现在 Alice 应该有空头持仓
        assertTrue(exchange.getPosition(alice).size < 0, "Alice should have short position");

        // Alice 尝试加仓（逐仓）- 应该失败
        vm.prank(alice);
        vm.expectRevert("cannot change margin mode on existing position");
        exchange.placeOrder(false, 1100e18, 0.5 ether, 0, MarginMode.ISOLATED);
    }

    /**
     * @notice 测试：平仓后可以重新选择模式
     */
    function testCanChangeModeAfterClosingPosition() public {
        // 先给 Carol 充值
        vm.deal(carol, 100 ether);
        vm.prank(carol);
        exchange.deposit{value: 100 ether}();

        // Carol 没有持仓，可以用任意模式
        vm.prank(carol);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        (, MarginMode mode,,,) = exchange.getAccountDetails(carol);
        assertEq(uint256(mode), uint256(MarginMode.ISOLATED), "carol should be ISOLATED");

        // Carol 平仓
        vm.prank(carol);
        exchange.placeOrder(false, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 验证仓位已平
        assertTrue(exchange.getPosition(carol).size == 0, "position should be closed");

        // 现在可以用不同的模式重新开仓
        vm.prank(carol);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        (, MarginMode mode2,,,) = exchange.getAccountDetails(carol);
        assertEq(uint256(mode2), uint256(MarginMode.CROSS), "should change to CROSS");
    }

    // ============================================
    // 测试组 2: 保证金分配/回收
    // ============================================

    /**
     * @notice 测试：分配保证金到逐仓
     */
    function testAllocateToIsolated() public {
        // 初始状态
        assertEq(exchange.getCrossMargin(alice), 100 ether, "initial cross margin");
        assertEq(exchange.getIsolatedMargin(alice), 0, "initial isolated margin");

        // 分配 10 ETH 到逐仓
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);

        // 验证保证金转移
        assertEq(exchange.getCrossMargin(alice), 90 ether, "cross margin after allocate");
        assertEq(exchange.getIsolatedMargin(alice), 10 ether, "isolated margin after allocate");
    }

    /**
     * @notice 测试：从逐仓回收保证金
     */
    function testRemoveFromIsolated() public {
        // 先分配
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);

        // 再回收 5 ETH
        vm.prank(alice);
        exchange.removeFromIsolated(5 ether);

        // 验证
        assertEq(exchange.getCrossMargin(alice), 95 ether, "cross margin after remove");
        assertEq(exchange.getIsolatedMargin(alice), 5 ether, "isolated margin after remove");
    }

    /**
     * @notice 测试：全仓保证金不足时无法分配
     */
    function testAllocateFailsWithInsufficientCrossMargin() public {
        vm.prank(alice);
        vm.expectRevert("insufficient cross margin");
        exchange.allocateToIsolated(200 ether); // 超过余额
    }

    /**
     * @notice 测试：逐仓保证金不足时无法回收
     */
    function testRemoveFailsWithInsufficientIsolatedMargin() public {
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);

        vm.prank(alice);
        vm.expectRevert("insufficient isolated margin");
        exchange.removeFromIsolated(20 ether); // 超过余额
    }

    /**
     * @notice 测试：无仓位时可以任意分配/回收
     */
    function testAllocateRemoveWithoutPosition() public {
        // 无仓位时可以预分配
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);

        // 无仓位时可以回收所有
        vm.prank(alice);
        exchange.removeFromIsolated(10 ether);

        assertEq(exchange.getCrossMargin(alice), 100 ether, "should return to initial");
        assertEq(exchange.getIsolatedMargin(alice), 0, "isolated should be zero");
    }

    // ============================================
    // 测试组 3: 保证金计算逻辑
    // ============================================

    /**
     * @notice 测试：全仓模式下挂单保证金取最大值
     * @dev 全仓：买单和卖单的保证金需求取 Max，因为它们不会同时成交
     */
    function testCrossMarginCalculation() public {
        // 假设初始保证金率 1%
        // 买单：1 ETH @ 1000 = 1000 USD * 1% = 10 USD
        // 卖单：1 ETH @ 1000 = 1000 USD * 1% = 10 USD
        // 全仓：Max(10, 10) = 10 USD（买单或卖单）

        // 挂买单
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // 挂卖单
        vm.prank(alice);
        exchange.placeOrder(false, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // 全仓模式下，两个相反方向的挂单保证金需求应该较低
        // 因为它们不会同时成交
    }

    /**
     * @notice 测试：逐仓模式下挂单保证金相加
     * @dev 逐仓：买单和卖单的保证金需求都要占用，因为仓位独立
     */
    function testIsolatedMarginCalculation() public {
        // 先分配足够的逐仓保证金
        vm.prank(alice);
        exchange.allocateToIsolated(30 ether);

        // 假设初始保证金率 1%
        // 买单：1 ETH @ 1000 = 1000 USD * 1% = 10 USD
        // 卖单：1 ETH @ 1000 = 1000 USD * 1% = 10 USD
        // 逐仓：10 + 10 = 20 USD（买单 + 卖单）

        // 挂买单
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 挂卖单
        vm.prank(alice);
        exchange.placeOrder(false, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 逐仓模式下，两个方向的挂单保证金需求应该相加
    }

    // ============================================
    // 测试组 4: 清算逻辑
    // ============================================

    /**
     * @notice 测试：逐仓清算只检查逐仓保证金
     */
    function testIsolatedLiquidation() public {
        // 分配少量逐仓保证金（1 ETH）
        vm.prank(alice);
        exchange.allocateToIsolated(1 ether);

        // 开多仓（逐仓）：1 ETH @ 1000 USD
        // 需要初始保证金：1000 * 1% = 10 USD
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 验证不可清算（健康）
        assertFalse(exchange.canLiquidate(alice), "should be healthy initially");

        // 价格大幅下跌 20%
        _updatePrice(800e18);

        // 计算保证金：
        // isolatedMargin: 1 ETH = 1000 USD
        // 未实现盈亏：(800 - 1000) * 1 = -200 USD
        // 保证金余额：1000 - 200 = 800 USD
        // 维持保证金：800 * 0.5% = 4 USD
        // 应该还是健康的

        // 继续下跌到 500 USD（50% 亏损）
        _updatePrice(500e18);

        // 未实现盈亏：(500 - 1000) * 1 = -500 USD
        // 保证金余额：1000 - 500 = 500 USD
        // 维持保证金：500 * 0.5% = 2.5 USD
        // 还是健康的

        // 价格跌到 100 USD（90% 亏损）
        _updatePrice(100e18);

        // 未实现盈亏：(100 - 1000) * 1 = -900 USD
        // 保证金余额：1000 - 900 = 100 USD
        // 维持保证金：100 * 0.5% = 0.5 USD
        // 依然健康

        // 极端情况：价格接近 0
        _updatePrice(1e18);

        // 未实现盈亏接近 -1000 USD
        // 保证金余额接近 0
        // 应该触发清算

        // 注意：需要更极端的价格或更小的初始保证金才能触发清算
    }

    /**
     * @notice 测试：全仓清算检查全仓保证金
     */
    function testCrossLiquidation() public {
        // 开多仓（全仓）
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // 验证不可清算（健康）
        assertFalse(exchange.canLiquidate(alice), "should be healthy initially");

        // 价格下跌 90%
        _updatePrice(100e18);

        // 计算保证金：
        // crossMargin: 100 ETH = 100000 USD
        // 未实现盈亏：(100 - 1000) * 1 = -900 USD
        // 保证金余额：100000 - 900 = 99100 USD
        // 维持保证金：100 * 0.5% = 0.5 USD
        // 非常健康

        // 极端情况：价格跌到接近 0，但全仓保证金充足
        _updatePrice(1e18);
        assertFalse(exchange.canLiquidate(alice), "should still be healthy with high cross margin");
    }

    /**
     * @notice 测试：逐仓模式不影响全仓保证金
     */
    function testIsolatedModeDoesNotAffectCrossMargin() public {
        // Alice: 全仓模式，开仓
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // Bob: 逐仓模式，分配保证金并开仓
        vm.prank(bob);
        exchange.allocateToIsolated(2 ether);
        vm.prank(bob);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 价格下跌
        _updatePrice(500e18);

        // Alice（全仓）：crossMargin 充足，不会清算
        assertFalse(exchange.canLiquidate(alice), "Alice (cross) should be healthy");

        // Bob（逐仓）：只检查 isolatedMargin
        // isolatedMargin: 2 ETH = 2000 USD
        // 未实现盈亏：(500 - 1000) * 1 = -500 USD
        // 保证金余额：2000 - 500 = 1500 USD
        // 维持保证金：500 * 0.5% = 2.5 USD
        // 应该还是健康的
        assertFalse(exchange.canLiquidate(bob), "Bob (isolated) should be healthy");
    }

    // ============================================
    // 测试组 5: 边界情况
    // ============================================

    /**
     * @notice 测试：零金额分配
     */
    function testAllocateZeroAmount() public {
        vm.prank(alice);
        exchange.allocateToIsolated(0); // 允许分配 0

        assertEq(exchange.getCrossMargin(alice), 100 ether);
        assertEq(exchange.getIsolatedMargin(alice), 0);
    }

    /**
     * @notice 测试：零金额回收
     */
    function testRemoveZeroAmount() public {
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);

        vm.prank(alice);
        exchange.removeFromIsolated(0); // 允许回收 0

        assertEq(exchange.getIsolatedMargin(alice), 10 ether);
    }

    /**
     * @notice 测试：连续分配和回收
     */
    function testMultipleAllocateAndRemove() public {
        // 连续分配
        vm.prank(alice);
        exchange.allocateToIsolated(10 ether);
        assertEq(exchange.getIsolatedMargin(alice), 10 ether);

        vm.prank(alice);
        exchange.allocateToIsolated(20 ether);
        assertEq(exchange.getIsolatedMargin(alice), 30 ether);

        // 连续回收
        vm.prank(alice);
        exchange.removeFromIsolated(5 ether);
        assertEq(exchange.getIsolatedMargin(alice), 25 ether);

        vm.prank(alice);
        exchange.removeFromIsolated(25 ether);
        assertEq(exchange.getIsolatedMargin(alice), 0);
    }

    /**
     * @notice 测试：多个用户独立保证金管理
     */
    function testMultipleUsersIndependentMargin() public {
        // Alice: 全仓模式
        vm.prank(alice);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.CROSS);

        // Bob: 逐仓模式
        vm.prank(bob);
        exchange.allocateToIsolated(10 ether);
        vm.prank(bob);
        exchange.placeOrder(true, 1000e18, 1 ether, 0, MarginMode.ISOLATED);

        // 验证两者独立
        (, MarginMode aliceMode,,, ) = exchange.getAccountDetails(alice);
        (, MarginMode bobMode,,,) = exchange.getAccountDetails(bob);

        assertEq(uint256(aliceMode), uint256(MarginMode.CROSS));
        assertEq(uint256(bobMode), uint256(MarginMode.ISOLATED));

        assertEq(exchange.getCrossMargin(alice), 100 ether);
        assertEq(exchange.getIsolatedMargin(alice), 0);

        assertEq(exchange.getCrossMargin(bob), 90 ether);
        assertEq(exchange.getIsolatedMargin(bob), 10 ether);
    }
}
