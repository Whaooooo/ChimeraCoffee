#!/usr/bin/env bash
set -euo pipefail

# dev-init-db.sh - Initialize MongoDB with seed data for development
# This script is typically called by dev-start.sh, but can be run standalone
#
# Environment variables (all have defaults):
#   MONGO_HOST, MONGO_PORT, MONGO_DATABASE
#   MONGO_USERNAME, MONGO_PASSWORD, MONGO_AUTHENTICATION_DATABASE
#   ADMIN_USERNAME, ADMIN_PASSWORD
#   MAVEN_LOCAL_REPO (for jbcrypt jar)

# Auto-detect directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
    # We're in ChimeraCoffee/dev-scripts/ (new structure)
    BACKEND_DIR="${SCRIPT_DIR}/.."
else
    # We're in project_root/test/ (legacy structure)
    BACKEND_DIR="${SCRIPT_DIR}/../ChimeraCoffee"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[DB]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[DB]${NC} $*"; }
log_error() { echo -e "${RED}[DB]${NC} $*"; }
log_success() { echo -e "${GREEN}[DB]${NC} $*"; }

# Configuration with defaults
: "${MONGO_HOST:=127.0.0.1}"
: "${MONGO_PORT:=27017}"
: "${MONGO_DATABASE:=chimera_local}"
: "${MONGO_USERNAME:=chimera}"
: "${MONGO_PASSWORD:=chimera}"
: "${MONGO_AUTHENTICATION_DATABASE:=admin}"
: "${ADMIN_USERNAME:=admin}"
: "${ADMIN_PASSWORD:=admin123}"

MONGO_URI="mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/${MONGO_DATABASE}?authSource=${MONGO_AUTHENTICATION_DATABASE}"

# Verify MongoDB is accessible
log_info "Connecting to MongoDB at ${MONGO_HOST}:${MONGO_PORT}..."

if ! mongosh "$MONGO_URI" --quiet --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; then
    log_error "Cannot connect to MongoDB"
    log_error "URI: ${MONGO_URI//${MONGO_PASSWORD}/***}"
    exit 1
fi

log_success "Connected to MongoDB"

# Generate admin password hash using bcrypt
log_info "Generating admin password hash..."

# Find jbcrypt jar
if [[ -z "${JBCRYPT_JAR:-}" ]]; then
    if [[ -n "${MAVEN_LOCAL_REPO:-}" ]]; then
        JBCRYPT_JAR="${MAVEN_LOCAL_REPO}/org/mindrot/jbcrypt/0.4/jbcrypt-0.4.jar"
    elif [[ -n "${MAVEN_USER_HOME:-}" ]]; then
        JBCRYPT_JAR="${MAVEN_USER_HOME}/repository/org/mindrot/jbcrypt/0.4/jbcrypt-0.4.jar"
    else
        JBCRYPT_JAR="${BACKEND_DIR}/.m2/repository/org/mindrot/jbcrypt/0.4/jbcrypt-0.4.jar"
    fi
fi

if [[ ! -f "$JBCRYPT_JAR" ]]; then
    log_warn "jbcrypt jar not found at $JBCRYPT_JAR"
    log_info "Attempting to download with Maven..."
    
    mkdir -p "${BACKEND_DIR}/.m2"
    mvn dependency:get \
        -Dartifact=org.mindrot:jbcrypt:0.4 \
        -Dmaven.repo.local="${BACKEND_DIR}/.m2/repository" \
        -q
    
    JBCRYPT_JAR="${BACKEND_DIR}/.m2/repository/org/mindrot/jbcrypt/0.4/jbcrypt-0.4.jar"
fi

if [[ ! -f "$JBCRYPT_JAR" ]]; then
    log_error "Could not obtain jbcrypt jar"
    exit 1
fi

# Create temporary directory for compilation
TMP_DIR="${BACKEND_DIR}/.tmp/bcrypt-$$"
mkdir -p "$TMP_DIR"

# Compile and run password hasher
cat > "${TMP_DIR}/HashPw.java" <<'JAVA'
import org.mindrot.jbcrypt.BCrypt;
public class HashPw {
    public static void main(String[] args) {
        if (args.length < 1) {
            System.err.println("Usage: HashPw <password>");
            System.exit(1);
        }
        System.out.print(BCrypt.hashpw(args[0], BCrypt.gensalt()));
    }
}
JAVA

javac -cp "$JBCRYPT_JAR" "${TMP_DIR}/HashPw.java" 2>/dev/null
ADMIN_PASSWORD_HASH=$(java -cp "$JBCRYPT_JAR:$TMP_DIR" HashPw "$ADMIN_PASSWORD")
rm -rf "$TMP_DIR"

log_success "Password hash generated"

# Seed database
log_info "Seeding database..."

export MONGO_DATABASE ADMIN_USERNAME ADMIN_PASSWORD_HASH

mongosh "$MONGO_URI" --quiet <<'MONGOSCRIPT'
const dbName = process.env.MONGO_DATABASE;
const adminUser = process.env.ADMIN_USERNAME;
const adminHash = process.env.ADMIN_PASSWORD_HASH;

const db = db.getSiblingDB(dbName);

// 1. Admin user
const userResult = db.user.updateOne(
    { name: adminUser, role: "ADMIN" },
    {
        $set: { hashedPassword: adminHash },
        $setOnInsert: {
            name: adminUser,
            role: "ADMIN",
            createdAt: new Date(),
            studentCert: false,
            expend: 0,
            orderNum: 0,
            points: 0
        }
    },
    { upsert: true }
);

if (userResult.upsertedCount > 0) {
    print('Created admin user: ' + adminUser);
} else {
    print('Updated admin user password: ' + adminUser);
}

// Helper function
function ensureInventory(name, unit, type, remain) {
    let doc = db.inventory.findOne({ name, deleted: false });
    if (!doc) {
        doc = {
            _id: new ObjectId(),
            name,
            unit,
            type,
            remain,
            deleted: false
        };
        db.inventory.insertOne(doc);
        print('Created inventory: ' + name);
    }
    return doc;
}

// 2. Inventory items
const coffeeBean = ensureInventory("Coffee Beans", "g", "raw", 10000);
const milk = ensureInventory("Milk", "ml", "raw", 5000);
const sugar = ensureInventory("Sugar", "g", "raw", 2000);

// 3. Product category
let cate = db.product_cate.findOne({ title: "Coffee", delete: 0 });
if (!cate) {
    cate = {
        _id: new ObjectId(),
        title: "Coffee",
        status: 1,
        priority: 1,
        delete: 0
    };
    db.product_cate.insertOne(cate);
    print('Created category: Coffee');
}

// 4. Product options
const sizeOptionValues = [
    { uuid: "size_small", value: "Small", priceAdjustment: 0, inventoryList: [] },
    { uuid: "size_large", value: "Large", priceAdjustment: 200, inventoryList: [{ uuid: milk._id.valueOf(), amount: 50 }] }
];

let sizeOption = db.product_option.findOne({ name: "Size" });
if (!sizeOption) {
    sizeOption = { _id: new ObjectId(), name: "Size", values: sizeOptionValues };
    db.product_option.insertOne(sizeOption);
    print('Created option: Size');
}

const tempOptionValues = [
    { uuid: "temp_hot", value: "Hot", priceAdjustment: 0, inventoryList: [] },
    { uuid: "temp_iced", value: "Iced", priceAdjustment: 0, inventoryList: [] }
];

let tempOption = db.product_option.findOne({ name: "Temperature" });
if (!tempOption) {
    tempOption = { _id: new ObjectId(), name: "Temperature", values: tempOptionValues };
    db.product_option.insertOne(tempOption);
    print('Created option: Temperature');
}

// 5. Sample products
const baseInventory = [
    { uuid: coffeeBean._id.valueOf(), amount: 18 },
    { uuid: milk._id.valueOf(), amount: 200 }
];

const latteOptions = {};
latteOptions[sizeOption._id.valueOf()] = sizeOptionValues;
latteOptions[tempOption._id.valueOf()] = tempOptionValues;

let latte = db.product.findOne({ name: "Latte", delete: 0 });
if (!latte) {
    db.product.insertOne({
        _id: new ObjectId(),
        cateId: cate._id,
        name: "Latte",
        imgURL: "",
        imgURL_small: "",
        price: 2400,
        stuPrice: 2200,
        describe: "Classic espresso with steamed milk",
        short_desc: "Espresso + Steamed Milk",
        status: 1,
        delete: 0,
        productOptions: latteOptions,
        needStockWithRestrictBuy: false,
        stock: 999,
        inventoryList: baseInventory,
        presaleNum: 0,
        stocked: true,
        onlyDining: false,
        onlyDelivery: false,
        no_coupon: false,
        rank: 1
    });
    print('Created product: Latte');
}

let americano = db.product.findOne({ name: "Americano", delete: 0 });
if (!americano) {
    db.product.insertOne({
        _id: new ObjectId(),
        cateId: cate._id,
        name: "Americano",
        imgURL: "",
        imgURL_small: "",
        price: 1800,
        stuPrice: 1600,
        describe: "Espresso with hot water",
        short_desc: "Espresso + Water",
        status: 1,
        delete: 0,
        productOptions: {},
        needStockWithRestrictBuy: false,
        stock: 999,
        inventoryList: [{ uuid: coffeeBean._id.valueOf(), amount: 18 }],
        presaleNum: 0,
        stocked: true,
        onlyDining: false,
        onlyDelivery: false,
        no_coupon: false,
        rank: 2
    });
    print('Created product: Americano');
}

// 6. State Machine Processor Map
// Clear existing mappings
db.processor_map.deleteMany({});

// Processor 0: NotifyPrePay - handles payment notification from PRE_PAID to PAID
// This applies to all customer types and all scenes
db.processor_map.insertOne({
    state: "预支付",
    event: "支付成功",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食", "外带", "定时达", "校庆场景"],
    processorIds: [0]
});

// Processor 1: NeedDineInFromAllTypesOfCustomer - from PAID to WAITING_DINE_IN
// Applies to all customer types for DINE_IN scene
db.processor_map.insertOne({
    state: "已支付",
    event: "需要堂食",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食"],
    processorIds: [1]
});

// Processor 8: NeedTakeOutFromAllTypesOfCustomer - from PAID to WAITING_TAKE_OUT
// Applies to all customer types for TAKE_OUT scene
db.processor_map.insertOne({
    state: "已支付",
    event: "需要外带",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["外带"],
    processorIds: [8]
});

// Processor 2: NeedFixDeliveryFromCertifiedStudent - from PAID to WAITING_FIX_DELIVERY
// Applies to certified students for FIX_DELIVERY scene
db.processor_map.insertOne({
    state: "已支付",
    event: "需要定时达",
    customerTypes: ["北大学生业务", "清华学生业务"],
    scenes: ["定时达"],
    processorIds: [2]
});

// Processor 3: SupplyDineIn - from WAITING_DINE_IN to NORMAL_END
db.processor_map.insertOne({
    state: "待出餐",
    event: "提供堂食",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食"],
    processorIds: [3]
});

// Processor 9: SupplyTakeOut - from WAITING_TAKE_OUT to NORMAL_END
db.processor_map.insertOne({
    state: "待出餐",
    event: "提供外带",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["外带"],
    processorIds: [9]
});

// Processor 4: SupplyFixDelivery - from WAITING_FIX_DELIVERY to NORMAL_END
db.processor_map.insertOne({
    state: "待配送",
    event: "提供定时达",
    customerTypes: ["北大学生业务", "清华学生业务"],
    scenes: ["定时达"],
    processorIds: [4]
});

// Processor 10: RefundApply - can be applied to multiple states
db.processor_map.insertOne({
    state: "已支付",
    event: "退款申请",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食", "外带", "定时达", "校庆场景"],
    processorIds: [10]
});

db.processor_map.insertOne({
    state: "待出餐",
    event: "退款申请",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食", "外带", "定时达", "校庆场景"],
    processorIds: [10]
});

db.processor_map.insertOne({
    state: "待配送",
    event: "退款申请",
    customerTypes: ["北大学生业务", "清华学生业务"],
    scenes: ["定时达"],
    processorIds: [10]
});

// Processor 11: RefundCallBack - handles refund notification
db.processor_map.insertOne({
    state: "等待退款通知",
    event: "退款结果通知",
    customerTypes: ["北大学生业务", "清华学生业务", "未学生认证业务"],
    scenes: ["堂食", "外带", "定时达", "校庆场景"],
    processorIds: [11]
});

print('Created processor_map entries');

// 7. App Configuration (required for order processing)
const appConfigs = [
    { key: "dineInController", value: "开", desc: "堂食开关：开/关" },
    { key: "deliveryController", value: "开", desc: "定时达开关：开/关" },
    { key: "points_conversion_ratio", value: "10", desc: "积分兑换比例（分）" },
    { key: "the_period_of_time", value: "300000", desc: "自动发送供餐事件的延迟时间（毫秒）" },
    { key: "periodically_send_event_switch", value: "F", desc: "定时发送事件开关：T/F" },
    { key: "periodically_send_event_start_time", value: "08:00", desc: "定时发送事件开始时间" },
    { key: "periodically_send_event_end_time", value: "22:00", desc: "定时发送事件结束时间" },
    { key: "contact_phone_number", value: "13800138000", desc: "联系电话" },
    { key: "shop_address", value: "清华大学", desc: "店铺地址" }
];

appConfigs.forEach(cfg => {
    const result = db.app_configuration.updateOne(
        { key: cfg.key },
        { 
            $set: { value: cfg.value },
            $setOnInsert: { 
                key: cfg.key,
                createdAt: new Date(),
                updatedAt: new Date()
            }
        },
        { upsert: true }
    );
    if (result.upsertedCount > 0) {
        print('Created app_config: ' + cfg.key + ' = ' + cfg.value);
    } else {
        print('Updated app_config: ' + cfg.key + ' = ' + cfg.value);
    }
});

print('Database seeding complete!');
MONGOSCRIPT

log_success "Database initialization complete"
log_info "Admin user: ${ADMIN_USERNAME} / ${ADMIN_PASSWORD}"
