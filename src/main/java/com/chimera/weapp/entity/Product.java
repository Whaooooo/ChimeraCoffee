package com.chimera.weapp.entity;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotNull;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;
import com.chimera.weapp.vo.OptionValue;
import com.chimera.weapp.vo.InventoryUsage;
import org.bson.types.ObjectId;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

import java.util.List;
import java.util.Map;

@Document(collection = "product")
@Data
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Product {
    @Id
    private ObjectId id;
    @Schema(description = "对应ProductCate.id")
    @NotNull
    private ObjectId cateId;
    private String name;
    @Schema(description = "菜单详情图")
    private String imgURL;
    @Schema(description = "菜单首页缩略图")
    private String imgURL_small;
    @Schema(description = "基础价格，单位为分")
    private int price;
    @Schema(description = "学生优惠价。若用户为已认证学生，展示基础价格，然后划掉，再展示学生优惠价。若未认证则正常展示基础价格。单位为分。")
    private int stuPrice;
    @Schema(description = "详情页描述")
    private String describe;
    @Schema(description = "菜单列表中，name下面展示的简介")
    private String short_desc;
    @Schema(description = "status=0为下架，后端不返回给前端")
    private int status; // 0是下架，1是上架
    @Schema(description = "对于delete=1的，后端不返回")
    private int delete; // 1是删除，0是正常
    @Schema(description = "加购商品的可选项, key=ProductOption.id")
    private Map<String, List<OptionValue>> productOptions; // String为option的objectId
    @Schema(description = "是否需要库存管理/限制购买，前端判断为True时限购一单")
    private Boolean needStockWithRestrictBuy;
    @Schema(description = "库存数量，为0时前端提示已售罄并不可下单")
    private int stock;
    @Schema(description = "原料信息和用量列表")
    private List<InventoryUsage> inventoryList;
    @Schema(description = "预售买数量，补货后清零")
    private int presaleNum;
    @Schema(description = "当天是否已补货，0点设为False")
    private Boolean stocked;
    @Schema(description = "是否只限堂食，为true时定时达页面不显示该商品")
    private Boolean onlyDining;
    @Schema(description = "是否只限定时达，为true时堂食页面不显示该商品")
    private Boolean onlyDelivery;

    @Schema(description = "是否不能用优惠券，为true时不能用")
    private Boolean no_coupon;

    @Schema(description = "rank 越大越靠前；允许为 null")
    private Integer rank;
}
