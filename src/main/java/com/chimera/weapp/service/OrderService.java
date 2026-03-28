package com.chimera.weapp.service;

import com.chimera.weapp.apiparams.OrderApiParams;
import com.chimera.weapp.apiparams.OrderItemApiParams;
import com.chimera.weapp.dto.UserDTO;
import com.chimera.weapp.entity.*;
import com.chimera.weapp.repository.*;
import com.chimera.weapp.statemachine.context.StateContext;
import com.chimera.weapp.statemachine.engine.OrderFsmEngine;
import com.chimera.weapp.statemachine.enums.ErrorCodeEnum;
import com.chimera.weapp.statemachine.exception.FsmException;
import com.chimera.weapp.util.BusinessHoursValidator;
import com.chimera.weapp.util.ThreadLocalUtil;
import com.chimera.weapp.util.TimeRangeChecker;
import com.chimera.weapp.vo.CouponIns;
import com.chimera.weapp.vo.OptionValue;
import com.chimera.weapp.vo.OrderItem;
import lombok.extern.slf4j.Slf4j;
import org.bson.types.ObjectId;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.time.DayOfWeek;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.*;
import java.util.List;

import static com.chimera.weapp.repository.AppConfigurationRepository.*;

@Slf4j
@Component
public class OrderService {
    @Autowired
    private OrderRepository orderRepository;
    @Autowired
    private ProductRepository productRepository;
    @Autowired
    private ProductOptionRepository productOptionRepository;
    @Autowired
    private UserRepository userRepository;
    @Autowired
    private OrderFsmEngine orderFsmEngine;
    @Autowired
    private AppConfigurationRepository appConfigurationRepository;

    public Order buildOrderByApiParams(OrderApiParams orderApiParams) throws Exception {
        String dineInControllerValue = appConfigurationRepository.findByKey("dineInController")
                .map(AppConfiguration::getValue)
                .orElseThrow(() -> new Exception("dineInController配置未找到"));

        String deliveryControllerValue = appConfigurationRepository.findByKey("deliveryController")
                .map(AppConfiguration::getValue)
                .orElseThrow(() -> new Exception("deliveryController配置未找到"));

        // 判断是否在营业时间内（用于 auto 模式）
        boolean isWithinBusinessHours = checkWithinBusinessHours();

        // 处理 dineInController: 开/关/auto
        boolean dineInController = resolveControllerStatus(dineInControllerValue, isWithinBusinessHours, "dineInController");

        // 处理 deliveryController: 开/关/auto
        boolean deliveryController = resolveControllerStatus(deliveryControllerValue, isWithinBusinessHours, "deliveryController");

        String scene = orderApiParams.getScene();

        // 1. 当两个 bool 都是 false 时，抛出异常
        if (!dineInController && !deliveryController) {
            throw new Exception("奇美拉咖啡休息中~");
        }

        // 2. 当 dineInController 为 false，并且 scene 为“堂食”或“外带”时，抛出异常
        if (!dineInController && ("堂食".equals(scene) || "外带".equals(scene))) {
            throw new Exception("到店暂停开放，可选择定时达~");
        }

        // 3. 当 deliveryController 为 false，并且 scene 为“定时达”时，抛出异常
        if (!deliveryController && "定时达".equals(scene)) {
            throw new Exception("定时达暂停开放，欢迎到店品咖~");
        }


        List<OrderItem> orderItems = buildItemsByApiParams(orderApiParams.getItems());
        Order.OrderBuilder orderBuilder = Order.builder().userId(orderApiParams.getUserId())
                .customerType(orderApiParams.getCustomerType())
                .scene(orderApiParams.getScene())
                .deliveryInfo(orderApiParams.getDeliveryInfo())
                .items(orderItems)
                .remark(orderApiParams.getRemark())
                .merchantNote(orderApiParams.getMerchantNote());

        // 如果 DeliveryInfo 不为空，更新用户的电话号码
        if (orderApiParams.getDeliveryInfo() != null && orderApiParams.getDeliveryInfo().getNumber() != null) {
            User user = userRepository.findById(orderApiParams.getUserId()).orElse(null);
            if (user != null) {
                user.setNumber(orderApiParams.getDeliveryInfo().getNumber());
                user.setDeliveryInfo(orderApiParams.getDeliveryInfo());
                userRepository.save(user);
            }
        }

        // 库存判断
        Map<ObjectId, Integer> productsToUpdate = new HashMap<>();

        // 定义 OptionValue.value 到整数的映射
        Map<String, Integer> optionValueMap = new HashMap<>();
        optionValueMap.put("一个", 1);
        optionValueMap.put("两个", 2);
        optionValueMap.put("三个", 3);

        for (OrderItem item : orderItems) {
            // 获取对应的 Product
            Product product = productRepository.findById(item.getProductId()).orElseThrow(() ->
                    new IllegalArgumentException("Product not found for ID: " + item.getProductId())
            );

            if (Boolean.TRUE.equals(product.getNeedStockWithRestrictBuy())) {
                // 假设每个 OrderItem 的 optionValues 只有一个键值对
                if (item.getOptionValues() != null && item.getOptionValues().size() == 1) {
                    OptionValue optionValue = item.getOptionValues().values().iterator().next();
                    String valueStr = optionValue.getValue();
                    Integer quantity = optionValueMap.get(valueStr);
                    if (quantity != null) {
                        // 如果同一个产品多次出现，累加数量
                        productsToUpdate.merge(product.getId(), quantity, Integer::sum);
                    } else {
                        throw new IllegalArgumentException("Unknown OptionValue: " + valueStr);
                    }
                } else {
                    throw new IllegalArgumentException("OrderItem optionValues is invalid for OrderItem: " + item.getProductId());
                }
            }
        }

        // 5. 检查库存是否足够
        List<String> outOfStockProducts = new ArrayList<>();
        List<String> insufficientProducts = new ArrayList<>();
        for (Map.Entry<ObjectId, Integer> entry : productsToUpdate.entrySet()) {
            ObjectId productId = entry.getKey();
            int requiredQuantity = entry.getValue();

            Product product = productRepository.findById(productId).orElseThrow(() ->
                    new IllegalArgumentException("Product not found for ID: " + productId)
            );

            if (product.getStock() == 0) {
                // 使用 [] 括起商品名称
                outOfStockProducts.add("[" + product.getName() + "]");
            } else if (product.getStock() < requiredQuantity) {
                insufficientProducts.add(String.format("[%s]仅剩%d个库存", product.getName(), product.getStock()));
            }
        }

        if (!outOfStockProducts.isEmpty() || !insufficientProducts.isEmpty()) {
            StringBuilder errorMessageBuilder = new StringBuilder();

            if (!outOfStockProducts.isEmpty()) {
                String outOfStockMessage = String.join("，", outOfStockProducts) + "当日已售罄，现在可以下单次日的定时达噢！";
                errorMessageBuilder.append(outOfStockMessage);
            }

            if (!insufficientProducts.isEmpty()) {
                String insufficientMessage = String.join("，", insufficientProducts) + "，不好意思少买一些吧~";
                errorMessageBuilder.append(insufficientMessage);
            }

            throw new Exception(errorMessageBuilder.toString());
        }


        int orderItemPriceSum = orderItems.stream().map(OrderItem::getPrice).reduce(Integer::sum).orElseThrow();

        int pointRatios = appConfigurationRepository.findByKey("points_conversion_ratio")
                .map(AppConfiguration::getValue)
                .map(Integer::parseInt)
                .orElseThrow(() -> new RuntimeException("积分兑换比例配置未找到"));

        int denominator = pointRatios * 100;
        if (denominator == 0) {
            throw new ArithmeticException("积分兑换，除数不能为零");
        }
        int points = (orderItemPriceSum + denominator - 1) / denominator;
        System.out.println("points："+points);
        orderBuilder.points(points);

        UserDTO userDTO = ThreadLocalUtil.get(ThreadLocalUtil.USER_DTO);
        if (!Objects.isNull(orderApiParams.getCouponInsUUID())) {
            CouponIns couponIns = getCouponInsFromUserByUUID(userDTO.getId(), orderApiParams.getCouponInsUUID(),
                    orderApiParams.getItems().stream().map(OrderItemApiParams::getProductId).toList());

            if (couponIns.getStatus() != 0) {
                throw new Exception("Coupon has already been used");
            }

            orderBuilder.coupon(couponIns);
            orderBuilder.totalPrice(orderItemPriceSum - couponIns.getDePrice());
        } else {
            orderBuilder.totalPrice(orderItemPriceSum);
        }

        // 获取当前日期的开始时间（0点）
        Date startOfDay = getStartOfDay(new Date());
        // 查询当天的订单数量
        long orderCountToday = orderRepository.countByCreatedAtGreaterThanEqual(startOfDay);
        // 设置订单号，从1开始累计
        orderBuilder.orderNum((int) orderCountToday + 1);
        return orderBuilder.build();
    }

    /**
     * 检查当前时间是否在营业时间内
     * @return true 如果当前时间在配置的营业时间段内
     */
    private boolean checkWithinBusinessHours() {
        try {
            ZoneId currentZone = ZoneId.systemDefault();
            ZonedDateTime now = ZonedDateTime.now(currentZone);
            DayOfWeek dayOfWeek = now.getDayOfWeek();
            int currentHour = now.getHour();
            int currentMinute = now.getMinute();

            // 判断今天是周末还是工作日
            boolean isWeekend = (dayOfWeek == DayOfWeek.SATURDAY || dayOfWeek == DayOfWeek.SUNDAY);
            String openingTimeKey = isWeekend ? "weekend_opening_hours" : "weekdays_opening_hours";

            // 获取营业时间配置
            String businessHours = appConfigurationRepository.findByKey(openingTimeKey)
                    .map(AppConfiguration::getValue)
                    .orElse(null);

            if (businessHours == null || businessHours.trim().isEmpty()) {
                log.warn("营业时间配置未找到: {}", openingTimeKey);
                return true; // 如果没有配置，默认允许订单
            }

            return BusinessHoursValidator.isWithinBusinessHours(businessHours, currentHour, currentMinute);
        } catch (Exception e) {
            log.error("检查营业时间出错", e);
            return true; // 出错时默认允许订单
        }
    }

    /**
     * 解析控制器状态
     * @param controllerValue 配置值: 开/关/auto
     * @param isWithinBusinessHours 是否在营业时间内
     * @param controllerName 控制器名称（用于错误提示）
     * @return true 如果允许订单
     */
    private boolean resolveControllerStatus(String controllerValue, boolean isWithinBusinessHours, String controllerName) {
        if ("开".equals(controllerValue)) {
            return true;
        } else if ("关".equals(controllerValue)) {
            return false;
        } else if ("auto".equals(controllerValue)) {
            return isWithinBusinessHours;
        } else {
            throw new RuntimeException("非法的 " + controllerName + " 配置值: " + controllerValue + "，必须是 开/关/auto 之一");
        }
    }

    public Order buildOrderByApiParamsShop(OrderApiParams orderApiParams) {
        List<OrderItem> orderItems = buildItemsByApiParams(orderApiParams.getItems());
        Order.OrderBuilder orderBuilder = Order.builder().userId(orderApiParams.getUserId())
                .customerType(orderApiParams.getCustomerType())
                .scene(orderApiParams.getScene())
                .deliveryInfo(orderApiParams.getDeliveryInfo())
                .items(orderItems)
                .remark(orderApiParams.getRemark())
                .merchantNote(orderApiParams.getMerchantNote())
                .disPrice(orderApiParams.getDisPrice());

        int orderItemPriceSum = orderItems.stream().map(OrderItem::getPrice).reduce(Integer::sum).orElseThrow();
        UserDTO userDTO = ThreadLocalUtil.get(ThreadLocalUtil.USER_DTO);
        if (!Objects.isNull(orderApiParams.getCouponInsUUID())) {
            CouponIns couponIns = getCouponInsFromUserByUUID(userDTO.getId(), orderApiParams.getCouponInsUUID(),
                    orderApiParams.getItems().stream().map(OrderItemApiParams::getProductId).toList());
            orderBuilder.coupon(couponIns);
            orderBuilder.totalPrice(orderItemPriceSum - couponIns.getDePrice());
        }
        orderBuilder.totalPrice(orderItemPriceSum - orderApiParams.getDisPrice());

        // 获取当前日期的开始时间（0点）
        Date startOfDay = getStartOfDay(new Date());
        // 查询当天的订单数量
        long orderCountToday = orderRepository.countByCreatedAtGreaterThanEqual(startOfDay);
        // 设置订单号，从1开始累计
        orderBuilder.orderNum((int) orderCountToday + 1);
        return orderBuilder.build();
    }

    public CouponIns getCouponInsFromUserByUUID(String userId, String couponInsUUIDInput, List<ObjectId> productIds) {
        User user = userRepository.findById(new ObjectId(userId)).orElseThrow();
        List<CouponIns> coupons = user.getCoupons();
        for (CouponIns couponIns : coupons) {
            String couponInsUUID = couponIns.getUuid();
            if (Objects.equals(couponInsUUID, couponInsUUIDInput)) {
                String cateId = couponIns.getCateId();
                if (Objects.isNull(cateId)) {
                    return couponIns;
                }
                for (ObjectId productId : productIds) {
                    Product product = productRepository.findById(productId).orElseThrow();
                    if (Objects.equals(product.getCateId().toHexString(), cateId)) {
                        return couponIns;
                    }
                }
            }
        }
        throw new RuntimeException("当前用户没有对应的优惠券或优惠券不适用于本订单中的任何一个商品");
    }

    public List<OrderItem> buildItemsByApiParams(List<OrderItemApiParams> items) {
        ArrayList<OrderItem> res = new ArrayList<>();
        for (OrderItemApiParams orderItemApiParams : items) {
            ObjectId productId = orderItemApiParams.getProductId();
            Product product = productRepository.findById(productId).orElseThrow();
            String name = product.getName();
            ObjectId cateId = product.getCateId();
            int actualOrderItemPrice = 0;
            actualOrderItemPrice += product.getPrice();
            Map<String, String> optionValues = orderItemApiParams.getOptionValues();
            HashMap<String, OptionValue> map = new HashMap<>();
            for (Map.Entry<String, String> entry : optionValues.entrySet()) {
                String optionId = entry.getKey();
                String optionValueUUID = entry.getValue();
                ProductOption actualProductOption = productOptionRepository.findById(new ObjectId(optionId)).orElseThrow();
                for (OptionValue actualOptionValue : actualProductOption.getValues()) {
                    if (Objects.equals(actualOptionValue.getUuid(), optionValueUUID)) {
                        map.put(optionId, actualOptionValue);
                        actualOrderItemPrice += actualOptionValue.getPriceAdjustment();
                        break;
                    }
                }
            }
            OrderItem orderItem = OrderItem.builder().productId(productId)
                    .optionValues(map)
                    .name(name)
                    .cateId(cateId)
                    .imgURL_small(product.getImgURL_small())
                    .price(actualOrderItemPrice).build();
            res.add(orderItem);
        }
        return res;
    }

    /**
     * 获取当天开始时间（0点）
     */
    private Date getStartOfDay(Date date) {
        Calendar calendar = Calendar.getInstance();
        calendar.setTime(date);
        calendar.set(Calendar.HOUR_OF_DAY, 0);
        calendar.set(Calendar.MINUTE, 0);
        calendar.set(Calendar.SECOND, 0);
        calendar.set(Calendar.MILLISECOND, 0);
        return calendar.getTime();
    }

    public String getDescriptionWhileLengthNotGreaterThen(Order order, int num) {
        List<String> list = getItemDescList(order);
        StringBuilder stringBuilder = new StringBuilder();
        while (!list.isEmpty()) {
            String remove = list.remove(0);
            int cur_length = stringBuilder.length();
            if (cur_length + remove.length() < num) {
                stringBuilder.append(remove);
            } else {
                stringBuilder.append("等");
                break;
            }
        }
        return stringBuilder.toString();
    }

    public String getDescriptionWhileByteLengthNotGreaterThen(Order order, int num) {
        List<String> list = getItemDescList(order);
        StringBuilder stringBuilder = new StringBuilder();
        while (!list.isEmpty()) {
            String remove = list.remove(0);
            String tmp= stringBuilder +remove;

            if (tmp.getBytes().length < num) {
                stringBuilder.append(remove);
            } else {
                stringBuilder.append("等");
                break;
            }
        }
        return stringBuilder.toString();
    }

    private List<String> getItemDescList(Order order) {
        TreeMap<String, Integer> treeMap = new TreeMap<>();

        for (OrderItem item : order.getItems()) {
            ObjectId productId = item.getProductId();
            Product product = productRepository.findById(productId).orElseThrow();
            String productName = product.getName();
            treeMap.put(productName, treeMap.getOrDefault(productName, 0) + 1);
        }
        List<String> list = new ArrayList<>();
        for (Map.Entry<String, Integer> entry : treeMap.entrySet()) {
            String name = entry.getKey();
            Integer count = entry.getValue();
            String str = name + "×" + count;
            list.add(str);
        }
        return list;
    }

    public void sendAnEventAfterACertainPeriodOfTime(ObjectId orderId, String event, Object context) {
        AppConfiguration time = appConfigurationRepository.findByKey(THE_PERIOD_OF_TIME).orElseThrow();
        String timeValue = time.getValue();
        if (checkCondition()) {
            new Thread(() -> {
                try {
                    Order order = orderRepository.findById(orderId).orElseThrow();
                    log.info("定时发送事件进入等待,id:{}", order.getId().toHexString());
                    Thread.sleep(Long.parseLong(timeValue));
                    orderFsmEngine.sendEvent(event, new StateContext<>(order, context));
                    log.info("定时发送事件完成,id:{}", order.getId().toHexString());
                } catch (FsmException e) {
                    if (Objects.equals(e.getMessage(), ErrorCodeEnum.NOT_FOUND_PROCESSOR.toString()) ||
                            Objects.equals(e.getMessage(), ErrorCodeEnum.FILTER_NOT_FOUND_PROCESSOR.toString()) ||
                            Objects.equals(e.getMessage(), ErrorCodeEnum.FOUND_MORE_PROCESSOR.toString())) {
                        log.info("定时发送事件失败，因为没到对应的状态机,id:{}", orderId.toHexString(), e);
                    } else {
                        log.error("定时发送事件失败，id:{}", orderId.toHexString());
                        throw new RuntimeException(e);
                    }
                } catch (Exception e) {
                    throw new RuntimeException(e);
                }
            }).start();
        }
    }


    private boolean checkCondition() {
        AppConfiguration switch_ = appConfigurationRepository.findByKey(PERIODICALLY_SEND_EVENT_SWITCH).orElseThrow();
        AppConfiguration start = appConfigurationRepository.findByKey(PERIODICALLY_SEND_EVENT_START_TIME).orElseThrow();
        AppConfiguration end = appConfigurationRepository.findByKey(PERIODICALLY_SEND_EVENT_END_TIME).orElseThrow();
        String switchValue = switch_.getValue();
        String startValue = start.getValue();
        String endValue = end.getValue();
        boolean open = Objects.equals(switchValue, "T");
        return open && TimeRangeChecker.isNowInTimeRange(startValue, endValue);
    }
}
