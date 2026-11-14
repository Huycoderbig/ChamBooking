-- =====================================================================
-- TỔNG QUAN FILE: Database/HotelBookingDB_v3.sql
-- - File này làm gì: Tạo CSDL cho website đặt phòng "Chạm" - bản 12 bảng
--   gọn cho demo (nhiều khách sạn, 8 điểm đến trọng điểm (TP.HCM, Hà Nội, Đà Nẵng, Đà Lạt, Nha Trang, Hạ Long, Bà Rịa - Vũng Tàu, Hội An), 48 khách sạn khác khu vực & giá phòng, ảnh riêng từng khu,
--   tiện nghi, mã giảm giá Loyalty, thanh toán, đánh giá).
-- - Nằm ở đâu: Thư mục Database/ của dự án ChamBooking.
-- - Cách chạy: Mở bằng SQL Server Management Studio (SQL Server 2016+)
--   rồi bấm Execute (F5). Script chạy lại được nhiều lần.
--
-- 12 BẢNG:
--   Danh mục  : Hotels, RoomTypes, RoomTypeImages, Rooms,
--               Amenities, RoomTypeAmenities (N-N)
--   Người dùng: Users
--   Nghiệp vụ : Coupons, Bookings, BookingDetails (N-N), Payments, Reviews
--
-- 2 TRIGGER:
--   (1) Tính tổng tiền đơn đặt phòng
--   (2) Cộng/trừ điểm Loyalty khi đơn chuyển sang/rời trạng thái Completed
--
-- CÁC KIỂM TRA VIẾT Ở CONTROLLER (C# + LINQ), KHÔNG ĐẶT TRONG DB:
--   - Chống đặt trùng phòng (phòng đã có đơn trùng ngày, phòng bảo trì)
--   - Kiểm tra & tính tiền giảm của mã giảm giá -> lưu vào DiscountAmount
--   - Số phòng không trùng trong cùng 1 khách sạn
--   - Tổng tiền thanh toán không vượt TotalAmount
--   - Đánh giá "Đã xác thực": BookingId thuộc đúng người dùng & đã Completed
--
-- LƯU Ý: Script XÓA và tạo lại các bảng trong HotelBookingDB.
-- =====================================================================
IF DB_ID(N'HotelBookingDB') IS NULL CREATE DATABASE HotelBookingDB;
GO
USE HotelBookingDB;
GO

-- Xóa view, hàm và bảng cũ (gồm cả bảng của bản v1, v2) để chạy lại được
DROP VIEW IF EXISTS vw_HotelRatingSummary;
DROP TABLE IF EXISTS BookingDetails;
DROP TABLE IF EXISTS Payments;
DROP TABLE IF EXISTS Reviews;
DROP TABLE IF EXISTS Bookings;
DROP TABLE IF EXISTS Coupons;
DROP TABLE IF EXISTS RoomTypeAmenities;
DROP TABLE IF EXISTS Amenities;
DROP TABLE IF EXISTS RoomTypeImages;
DROP TABLE IF EXISTS Rooms;
DROP TABLE IF EXISTS RoomTypes;
DROP TABLE IF EXISTS ResortZones;      -- bảng của bản v2 (nếu có)
DROP TABLE IF EXISTS Hotels;
DROP TABLE IF EXISTS Destinations;     -- bảng của bản v2 (nếu có)
DROP TABLE IF EXISTS Users;
DROP FUNCTION IF EXISTS dbo.fn_CalcCouponDiscount;   -- hàm của bản v2 (nếu có)
GO

-- =====================================================================
-- 1. TẠO BẢNG
-- =====================================================================

-- 1.1. Users: người dùng (Member / Admin)
CREATE TABLE Users (
    UserId        int           IDENTITY(1,1) NOT NULL,
    FullName      nvarchar(100) NOT NULL,
    Email         nvarchar(100) NOT NULL,
    PasswordHash  nvarchar(255) NOT NULL,   -- chỉ lưu mật khẩu đã băm
    PhoneNumber   nvarchar(20)  NULL,
    Role          nvarchar(20)  NOT NULL CONSTRAINT DF_Users_Role DEFAULT N'Member',
    LoyaltyPoints int           NOT NULL CONSTRAINT DF_Users_LoyaltyPoints DEFAULT 0,
    IsActive      bit           NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1,
    CreatedAt     datetime      NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT GETDATE(),
    CONSTRAINT PK_Users PRIMARY KEY (UserId),
    CONSTRAINT UQ_Users_Email UNIQUE (Email),
    CONSTRAINT CK_Users_Role CHECK (Role IN (N'Member', N'Admin'))
);

-- 1.2. Hotels: khách sạn / khu nghỉ dưỡng
--      City + Region dùng cho bộ lọc 20 tỉnh và Miền Bắc / Trung / Nam
CREATE TABLE Hotels (
    HotelId      int            IDENTITY(1,1) NOT NULL,
    HotelName    nvarchar(150)  NOT NULL,
    City         nvarchar(100)  NOT NULL,          -- VD: Đà Lạt, Hạ Long
    Region       nvarchar(20)   NOT NULL,          -- Miền Bắc / Miền Trung / Miền Nam
    Address      nvarchar(255)  NOT NULL,
    StarRating   tinyint        NOT NULL CONSTRAINT DF_Hotels_StarRating DEFAULT 4,
    Description  nvarchar(1000) NULL,
    ThumbnailUrl nvarchar(500)  NULL,
    IsActive     bit            NOT NULL CONSTRAINT DF_Hotels_IsActive DEFAULT 1,
    CreatedAt    datetime       NOT NULL CONSTRAINT DF_Hotels_CreatedAt DEFAULT GETDATE(),
    CONSTRAINT PK_Hotels PRIMARY KEY (HotelId),
    CONSTRAINT UQ_Hotels_HotelName UNIQUE (HotelName),
    CONSTRAINT CK_Hotels_Region CHECK (Region IN (N'Miền Bắc', N'Miền Trung', N'Miền Nam')),
    CONSTRAINT CK_Hotels_StarRating CHECK (StarRating BETWEEN 1 AND 5)
);

-- 1.3. RoomTypes: loại phòng của một khách sạn
--      ZoneName = tên phân khu (VD: Đồi Thông Tinh Mơ), NULL nếu khách sạn không chia khu
CREATE TABLE RoomTypes (
    RoomTypeId    int           IDENTITY(1,1) NOT NULL,
    HotelId       int           NOT NULL,
    ZoneName      nvarchar(150) NULL,
    TypeName      nvarchar(150) NOT NULL,
    Description   nvarchar(500) NULL,
    PricePerNight decimal(18,2) NOT NULL,
    OldPrice      decimal(18,2) NULL,             -- giá gạch ngang trên Card
    MaxGuests     int           NOT NULL CONSTRAINT DF_RoomTypes_MaxGuests DEFAULT 2,
    Area          int           NULL,             -- diện tích m²
    BedType       nvarchar(50)  NULL,             -- VD: 1 giường King
    ThumbnailUrl  nvarchar(500) NULL,
    CONSTRAINT PK_RoomTypes PRIMARY KEY (RoomTypeId),
    CONSTRAINT FK_RoomTypes_Hotels FOREIGN KEY (HotelId)
        REFERENCES Hotels(HotelId) ON DELETE NO ACTION,
    CONSTRAINT UQ_RoomTypes_Hotel_TypeName UNIQUE (HotelId, TypeName),
    CONSTRAINT CK_RoomTypes_PricePerNight CHECK (PricePerNight > 0),
    CONSTRAINT CK_RoomTypes_OldPrice CHECK (OldPrice IS NULL OR OldPrice >= PricePerNight),
    CONSTRAINT CK_RoomTypes_MaxGuests CHECK (MaxGuests BETWEEN 1 AND 20),
    CONSTRAINT CK_RoomTypes_Area CHECK (Area IS NULL OR Area > 0)
);

-- 1.4. RoomTypeImages: nhiều ảnh cho mỗi loại phòng (bộ sưu tập ảnh trên web)
CREATE TABLE RoomTypeImages (
    ImageId    int           IDENTITY(1,1) NOT NULL,
    RoomTypeId int           NOT NULL,
    ImageUrl   nvarchar(500) NOT NULL,
    Caption    nvarchar(200) NULL,                -- VD: Phòng tắm bồn đá
    SortOrder  int           NOT NULL CONSTRAINT DF_RoomTypeImages_SortOrder DEFAULT 0,
    CONSTRAINT PK_RoomTypeImages PRIMARY KEY (ImageId),
    CONSTRAINT FK_RoomTypeImages_RoomTypes FOREIGN KEY (RoomTypeId)
        REFERENCES RoomTypes(RoomTypeId) ON DELETE CASCADE
);

-- 1.5. Rooms: phòng vật lý
--      Số phòng không trùng trong cùng loại phòng; không trùng trong cùng
--      khách sạn thì kiểm tra ở Controller khi thêm/sửa phòng.
CREATE TABLE Rooms (
    RoomId     int          IDENTITY(1,1) NOT NULL,
    RoomTypeId int          NOT NULL,
    RoomNumber nvarchar(10) NOT NULL,
    Floor      int          NULL,
    IsActive   bit          NOT NULL CONSTRAINT DF_Rooms_IsActive DEFAULT 1,   -- 0 = đang bảo trì
    CONSTRAINT PK_Rooms PRIMARY KEY (RoomId),
    CONSTRAINT FK_Rooms_RoomTypes FOREIGN KEY (RoomTypeId)
        REFERENCES RoomTypes(RoomTypeId) ON DELETE NO ACTION,
    CONSTRAINT UQ_Rooms_RoomType_Number UNIQUE (RoomTypeId, RoomNumber)
);

-- 1.6. Amenities: danh mục tiện nghi (bảng "Tiện nghi và cơ sở vật chất")
CREATE TABLE Amenities (
    AmenityId   int           IDENTITY(1,1) NOT NULL,
    AmenityName nvarchar(100) NOT NULL,
    Category    nvarchar(30)  NOT NULL,
    CONSTRAINT PK_Amenities PRIMARY KEY (AmenityId),
    CONSTRAINT UQ_Amenities_Name UNIQUE (AmenityName),
    CONSTRAINT CK_Amenities_Category CHECK (Category IN
        (N'Internet', N'Thư giãn', N'An toàn', N'Dịch vụ', N'Trong phòng'))
);

-- 1.7. RoomTypeAmenities: bảng trung gian N-N giữa RoomTypes và Amenities
--      (Có thêm cột IsHighlighted để khi chạy Entity Framework Database First .edmx
--       sẽ luôn hiển thị đủ 12 bảng trên sơ đồ thực thể mà không bị EF ẩn thành đường nối N-N)
CREATE TABLE RoomTypeAmenities (
    RoomTypeId    int NOT NULL,
    AmenityId     int NOT NULL,
    IsHighlighted bit NOT NULL CONSTRAINT DF_RoomTypeAmenities_IsHighlighted DEFAULT 1,
    CONSTRAINT PK_RoomTypeAmenities PRIMARY KEY (RoomTypeId, AmenityId),
    CONSTRAINT FK_RoomTypeAmenities_RoomTypes FOREIGN KEY (RoomTypeId)
        REFERENCES RoomTypes(RoomTypeId) ON DELETE CASCADE,
    CONSTRAINT FK_RoomTypeAmenities_Amenities FOREIGN KEY (AmenityId)
        REFERENCES Amenities(AmenityId) ON DELETE CASCADE
);

-- 1.8. Coupons: mã giảm giá người dùng mới & Loyalty
--      Controller kiểm tra điều kiện và tính tiền giảm, rồi lưu vào Bookings.DiscountAmount
CREATE TABLE Coupons (
    CouponId         int           IDENTITY(1,1) NOT NULL,
    Code             nvarchar(30)  NOT NULL,      -- VD: CHAMBANMOI
    Title            nvarchar(200) NOT NULL,
    DiscountType     nvarchar(10)  NOT NULL,      -- Percent / Fixed
    DiscountValue    decimal(18,2) NOT NULL,      -- 15 (%) hoặc 250000 (đ)
    MaxDiscount      decimal(18,2) NULL,          -- trần giảm khi DiscountType = Percent
    MinOrderAmount   decimal(18,2) NOT NULL CONSTRAINT DF_Coupons_MinOrderAmount DEFAULT 0,
    MinLoyaltyPoints int           NOT NULL CONSTRAINT DF_Coupons_MinLoyaltyPoints DEFAULT 0,
    IsNewUserOnly    bit           NOT NULL CONSTRAINT DF_Coupons_IsNewUserOnly DEFAULT 0,
    StartDate        date          NOT NULL,
    EndDate          date          NOT NULL,
    IsActive         bit           NOT NULL CONSTRAINT DF_Coupons_IsActive DEFAULT 1,
    CONSTRAINT PK_Coupons PRIMARY KEY (CouponId),
    CONSTRAINT UQ_Coupons_Code UNIQUE (Code),
    CONSTRAINT CK_Coupons_DiscountType CHECK (DiscountType IN (N'Percent', N'Fixed')),
    CONSTRAINT CK_Coupons_DiscountValue CHECK (
        DiscountValue > 0 AND (DiscountType = N'Fixed' OR DiscountValue <= 100)),
    CONSTRAINT CK_Coupons_Dates CHECK (EndDate >= StartDate)
);

-- 1.9. Bookings: đơn đặt phòng
--      SubTotal    = tiền phòng (trigger tính từ BookingDetails x số đêm)
--      DiscountAmount = tiền giảm từ mã (Controller tính và lưu)
--      TotalAmount = SubTotal - DiscountAmount (trigger tính)
CREATE TABLE Bookings (
    BookingId      int            IDENTITY(1,1) NOT NULL,
    UserId         int            NOT NULL,
    CouponId       int            NULL,
    CheckInDate    date           NOT NULL,
    CheckOutDate   date           NOT NULL,
    SubTotal       decimal(18,2)  NOT NULL CONSTRAINT DF_Bookings_SubTotal DEFAULT 0,
    DiscountAmount decimal(18,2)  NOT NULL CONSTRAINT DF_Bookings_DiscountAmount DEFAULT 0,
    TotalAmount    decimal(18,2)  NOT NULL CONSTRAINT DF_Bookings_TotalAmount DEFAULT 0,
    Status         nvarchar(20)   NOT NULL CONSTRAINT DF_Bookings_Status DEFAULT N'Pending',
    SpecialRequest nvarchar(500)  NULL,
    CreatedAt      datetime       NOT NULL CONSTRAINT DF_Bookings_CreatedAt DEFAULT GETDATE(),
    CONSTRAINT PK_Bookings PRIMARY KEY (BookingId),
    CONSTRAINT FK_Bookings_Users FOREIGN KEY (UserId)
        REFERENCES Users(UserId) ON DELETE NO ACTION,
    CONSTRAINT FK_Bookings_Coupons FOREIGN KEY (CouponId)
        REFERENCES Coupons(CouponId) ON DELETE NO ACTION,
    CONSTRAINT CK_Bookings_Dates CHECK (CheckOutDate > CheckInDate),
    CONSTRAINT CK_Bookings_Amounts CHECK (SubTotal >= 0 AND DiscountAmount >= 0 AND TotalAmount >= 0),
    CONSTRAINT CK_Bookings_Status CHECK (Status IN (N'Pending', N'Confirmed', N'Completed', N'Cancelled'))
);

-- 1.10. BookingDetails: bảng trung gian N-N giữa Bookings và Rooms
CREATE TABLE BookingDetails (
    BookingId int           NOT NULL,
    RoomId    int           NOT NULL,
    UnitPrice decimal(18,2) NOT NULL,       -- giá một đêm, chốt tại thời điểm đặt
    CONSTRAINT PK_BookingDetails PRIMARY KEY (BookingId, RoomId),
    CONSTRAINT FK_BookingDetails_Bookings FOREIGN KEY (BookingId)
        REFERENCES Bookings(BookingId) ON DELETE CASCADE,
    CONSTRAINT FK_BookingDetails_Rooms FOREIGN KEY (RoomId)
        REFERENCES Rooms(RoomId) ON DELETE NO ACTION,
    CONSTRAINT CK_BookingDetails_UnitPrice CHECK (UnitPrice > 0)
);

-- 1.11. Payments: thanh toán (4 phương thức khớp trang Thanh toán)
CREATE TABLE Payments (
    PaymentId       int           IDENTITY(1,1) NOT NULL,
    BookingId       int           NOT NULL,
    PaymentMethod   nvarchar(50)  NOT NULL CONSTRAINT DF_Payments_PaymentMethod DEFAULT N'Cash',
    Amount          decimal(18,2) NOT NULL,
    PaymentDate     datetime      NOT NULL CONSTRAINT DF_Payments_PaymentDate DEFAULT GETDATE(),
    Status          nvarchar(20)  NOT NULL CONSTRAINT DF_Payments_Status DEFAULT N'Completed',
    TransactionCode nvarchar(100) NULL,     -- mã giao dịch MoMo / VietQR / thẻ
    CONSTRAINT PK_Payments PRIMARY KEY (PaymentId),
    CONSTRAINT FK_Payments_Bookings FOREIGN KEY (BookingId)
        REFERENCES Bookings(BookingId) ON DELETE NO ACTION,
    CONSTRAINT CK_Payments_Amount CHECK (Amount > 0),
    CONSTRAINT CK_Payments_Method CHECK (PaymentMethod IN (N'Cash', N'MoMo', N'VietQR', N'Card')),
    CONSTRAINT CK_Payments_Status CHECK (Status IN (N'Pending', N'Completed', N'Failed'))
);

-- 1.12. Reviews: đánh giá loại phòng, thang điểm 1-10 (khớp "9,4/10" trên web)
--       BookingId có giá trị = đánh giá đã xác thực
--       5 điểm thành phần dùng cho 5 thanh điểm trên trang Chi tiết
CREATE TABLE Reviews (
    ReviewId           int            IDENTITY(1,1) NOT NULL,
    UserId             int            NOT NULL,
    RoomTypeId         int            NOT NULL,
    BookingId          int            NULL,
    Rating             decimal(3,1)   NOT NULL CONSTRAINT DF_Reviews_Rating DEFAULT 10,
    CleanlinessScore   tinyint        NULL,
    LocationScore      tinyint        NULL,
    ServiceScore       tinyint        NULL,
    FacilitiesScore    tinyint        NULL,
    ValueForMoneyScore tinyint        NULL,
    Title              nvarchar(200)  NULL,
    Comment            nvarchar(1000) NULL,
    CreatedAt          datetime       NOT NULL CONSTRAINT DF_Reviews_CreatedAt DEFAULT GETDATE(),
    CONSTRAINT PK_Reviews PRIMARY KEY (ReviewId),
    CONSTRAINT FK_Reviews_Users FOREIGN KEY (UserId)
        REFERENCES Users(UserId) ON DELETE NO ACTION,
    CONSTRAINT FK_Reviews_RoomTypes FOREIGN KEY (RoomTypeId)
        REFERENCES RoomTypes(RoomTypeId) ON DELETE NO ACTION,
    CONSTRAINT FK_Reviews_Bookings FOREIGN KEY (BookingId)
        REFERENCES Bookings(BookingId) ON DELETE NO ACTION,
    CONSTRAINT CK_Reviews_Rating CHECK (Rating BETWEEN 1 AND 10),
    CONSTRAINT CK_Reviews_SubScores CHECK (
        (CleanlinessScore   IS NULL OR CleanlinessScore   BETWEEN 1 AND 10) AND
        (LocationScore      IS NULL OR LocationScore      BETWEEN 1 AND 10) AND
        (ServiceScore       IS NULL OR ServiceScore       BETWEEN 1 AND 10) AND
        (FacilitiesScore    IS NULL OR FacilitiesScore    BETWEEN 1 AND 10) AND
        (ValueForMoneyScore IS NULL OR ValueForMoneyScore BETWEEN 1 AND 10)),
    CONSTRAINT UQ_Reviews_User_RoomType UNIQUE (UserId, RoomTypeId)
);
GO

-- =====================================================================
-- 2. INDEX: tăng tốc tìm kiếm, lọc và nối bảng
-- =====================================================================
CREATE INDEX IX_Hotels_City_Region      ON Hotels(Region, City);
CREATE INDEX IX_RoomTypes_HotelId       ON RoomTypes(HotelId);
CREATE INDEX IX_RoomTypes_Price         ON RoomTypes(PricePerNight);   -- lọc khoảng giá
CREATE INDEX IX_RoomTypeImages_TypeId   ON RoomTypeImages(RoomTypeId, SortOrder);
CREATE INDEX IX_Bookings_UserId         ON Bookings(UserId);
CREATE INDEX IX_Bookings_Dates          ON Bookings(CheckInDate, CheckOutDate);
CREATE INDEX IX_BookingDetails_RoomId   ON BookingDetails(RoomId);
CREATE INDEX IX_Reviews_RoomTypeId      ON Reviews(RoomTypeId);
CREATE INDEX IX_Payments_BookingId      ON Payments(BookingId);
GO

-- =====================================================================
-- 3. TRIGGER
-- =====================================================================

-- 3.1. Thêm/xóa chi tiết đặt phòng -> tính lại SubTotal và TotalAmount
CREATE TRIGGER trg_BookingDetails_UpdateTotalAmount
ON BookingDetails
AFTER INSERT, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH AffectedBookings AS (
        SELECT BookingId FROM inserted
        UNION
        SELECT BookingId FROM deleted
    )
    UPDATE b
    SET b.SubTotal    = s.SubTotal,
        b.TotalAmount = CASE WHEN s.SubTotal > b.DiscountAmount
                             THEN s.SubTotal - b.DiscountAmount ELSE 0 END
    FROM Bookings b
    INNER JOIN AffectedBookings ab ON ab.BookingId = b.BookingId
    CROSS APPLY (
        SELECT ISNULL(SUM(bd.UnitPrice), 0) * DATEDIFF(DAY, b.CheckInDate, b.CheckOutDate) AS SubTotal
        FROM BookingDetails bd
        WHERE bd.BookingId = b.BookingId
    ) s;
END;
GO

-- 3.2. Khi cập nhật đơn đặt phòng:
--      (a) Đổi ngày nhận/trả phòng hoặc tiền giảm -> tính lại tiền
--      (b) Đổi trạng thái -> cộng điểm khi chuyển sang Completed,
--          trừ lại nếu đơn đang Completed bị chuyển sang trạng thái khác.
--          Cứ 100.000 đồng thực trả (TotalAmount) được 1 điểm.
CREATE TRIGGER trg_Bookings_AfterUpdate
ON Bookings
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- (a) Tính lại tiền
    IF UPDATE(CheckInDate) OR UPDATE(CheckOutDate) OR UPDATE(DiscountAmount)
    BEGIN
        UPDATE b
        SET b.SubTotal    = s.SubTotal,
            b.TotalAmount = CASE WHEN s.SubTotal > b.DiscountAmount
                                 THEN s.SubTotal - b.DiscountAmount ELSE 0 END
        FROM Bookings b
        INNER JOIN inserted i ON i.BookingId = b.BookingId
        CROSS APPLY (
            SELECT ISNULL(SUM(bd.UnitPrice), 0) * DATEDIFF(DAY, b.CheckInDate, b.CheckOutDate) AS SubTotal
            FROM BookingDetails bd
            WHERE bd.BookingId = b.BookingId
        ) s;
    END;

    -- (b) Điểm tích lũy
    IF UPDATE(Status)
    BEGIN
        UPDATE u
        SET u.LoyaltyPoints = u.LoyaltyPoints + p.Points
        FROM Users u
        INNER JOIN (
            SELECT b.UserId,
                   SUM(CASE
                           WHEN b.Status = N'Completed' AND d.Status <> N'Completed'
                               THEN CAST(FLOOR(b.TotalAmount / 100000) AS int)
                           WHEN d.Status = N'Completed' AND b.Status <> N'Completed'
                               THEN -CAST(FLOOR(d.TotalAmount / 100000) AS int)
                           ELSE 0
                       END) AS Points
            FROM Bookings b
            INNER JOIN deleted d ON d.BookingId = b.BookingId
            GROUP BY b.UserId
        ) p ON p.UserId = u.UserId
        WHERE p.Points <> 0;
    END;
END;
GO

-- =====================================================================
-- 4. VIEW: điểm trung bình, số đánh giá & giá thấp nhất của từng khách sạn
--    (dùng cho Card khách sạn "9,4/10 (256 đánh giá)" trên trang chủ)
-- =====================================================================
CREATE VIEW vw_HotelRatingSummary
AS
SELECT h.HotelId,
       h.HotelName,
       h.City,
       h.Region,
       MIN(rt.PricePerNight)                AS MinPrice,
       CAST(AVG(rv.Rating) AS decimal(3,1)) AS AvgRating,
       COUNT(DISTINCT rv.ReviewId)          AS ReviewCount
FROM Hotels h
LEFT JOIN RoomTypes rt ON rt.HotelId = h.HotelId
LEFT JOIN Reviews rv   ON rv.RoomTypeId = rt.RoomTypeId
GROUP BY h.HotelId, h.HotelName, h.City, h.Region;
GO


-- =====================================================================
-- 5. DỮ LIỆU MẪU (8 ĐỊA ĐIỂM TRỌNG ĐIỂM x 6 KHÁCH SẠN KHÁC KHU VỰC = 48 KHÁCH SẠN)
-- =====================================================================

-- 5.1. Người dùng (mật khẩu chỉ để demo; ứng dụng thật phải băm bằng BCrypt/PBKDF2)
INSERT INTO Users (FullName, Email, PasswordHash, PhoneNumber, Role) VALUES
(N'Nguyễn Quản Trị', N'admin@hotelbooking.vn', N'DEMO_HASH_ADMIN', N'0901000001', N'Admin'),
(N'Nguyễn Minh Khuê', N'minhkhue@gmail.com',   N'DEMO_HASH_USER2', N'0901000002', N'Member'),
(N'Trần Hoàng Nam',   N'hoangnam@gmail.com',   N'DEMO_HASH_USER3', N'0901000003', N'Member'),
(N'Lê Thảo Vy',       N'thaovy@gmail.com',     N'DEMO_HASH_USER4', N'0901000004', N'Member'),
(N'Phạm Quốc Bảo',    N'quocbao@gmail.com',    N'DEMO_HASH_USER5', N'0901000005', N'Member'),
(N'Đặng Thu Hà',      N'thuha@gmail.com',      N'DEMO_HASH_USER6', N'0901000006', N'Member');

-- 5.2. 48 khách sạn tại 8 điểm đến (TP. Hồ Chí Minh, Hà Nội, Đà Nẵng, Đà Lạt, Nha Trang, Hạ Long, Bà Rịa - Vũng Tàu, Hội An)
INSERT INTO Hotels (HotelName, City, Region, Address, StarRating, Description, ThumbnailUrl) VALUES
(N'The Reverie Saigon Đồng Khởi', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Phố Đi Bộ Nguyễn Huệ - Quận 1, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Phố Đi Bộ Nguyễn Huệ - Quận 1, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80'),
(N'Landmark 81 Skyview Luxury Residence', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Vinhomes Tân Cảng - Bình Thạnh, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Vinhomes Tân Cảng - Bình Thạnh, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=700&q=80'),
(N'Mia Saigon Boutique River Villa', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Biệt Thự Ven Sông Thảo Điền - Quận 2, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Biệt Thự Ven Sông Thảo Điền - Quận 2, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=700&q=80'),
(N'Park Hyatt Saigon Opera House', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Nhà Hát Thành Phố - Công Trường Lam Sơn, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Nhà Hát Thành Phố - Công Trường Lam Sơn, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?auto=format&fit=crop&w=700&q=80'),
(N'Crescent Lake Phú Mỹ Hưng Suites', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=700&q=80'),
(N'Bến Bạch Đằng Heritage Boutique Hotel', N'TP. Hồ Chí Minh', N'Miền Nam', N'Khu Bến Du Thuyền Bạch Đằng - Quận 1, TP. Hồ Chí Minh', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bến Du Thuyền Bạch Đằng - Quận 1, TP. Hồ Chí Minh.', N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=700&q=80'),
(N'Capella Hanoi Opera Heritage', N'Hà Nội', N'Miền Bắc', N'Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm, Hà Nội.', N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=700&q=80'),
(N'InterContinental Hanoi Westlake', N'Hà Nội', N'Miền Bắc', N'Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây, Hà Nội.', N'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=700&q=80'),
(N'Peridot Grand Phố Hàng Trống', N'Hà Nội', N'Miền Bắc', N'Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn, Hà Nội.', N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=700&q=80'),
(N'Lotte Center Sky Panorama Ba Đình', N'Hà Nội', N'Miền Bắc', N'Khu Đào Tấn - Liễu Giai Quận Ba Đình, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đào Tấn - Liễu Giai Quận Ba Đình, Hà Nội.', N'https://images.unsplash.com/photo-1584132967334-10e028bd69f7?auto=format&fit=crop&w=700&q=80'),
(N'Làng Cổ Đường Lâm Sơn Tây Retreat', N'Hà Nội', N'Miền Bắc', N'Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì, Hà Nội.', N'https://images.unsplash.com/photo-1596394516093-501ba68a0ba6?auto=format&fit=crop&w=700&q=80'),
(N'Tràng Tiền French Quarter Boutique', N'Hà Nội', N'Miền Bắc', N'Khu Phố Pháp Tràng Tiền - Hồ Gươm, Hà Nội', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Phố Pháp Tràng Tiền - Hồ Gươm, Hà Nội.', N'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=700&q=80'),
(N'InterContinental Sun Peninsula Sơn Trà', N'Đà Nẵng', N'Miền Trung', N'Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà, Đà Nẵng.', N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=700&q=80'),
(N'Sala Danang Beachfront Mỹ Khê', N'Đà Nẵng', N'Miền Trung', N'Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp, Đà Nẵng.', N'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?auto=format&fit=crop&w=700&q=80'),
(N'Hyatt Regency Non Nước Ocean Villa', N'Đà Nẵng', N'Miền Trung', N'Khu Bãi Biển Non Nước - Ngũ Hành Sơn, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bãi Biển Non Nước - Ngũ Hành Sơn, Đà Nẵng.', N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=700&q=80'),
(N'Novotel Danang Premier Sông Hàn', N'Đà Nẵng', N'Miền Trung', N'Khu Bờ Tây Sông Hàn - Cầu Rồng, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bờ Tây Sông Hàn - Cầu Rồng, Đà Nẵng.', N'https://images.unsplash.com/photo-1568084680786-a84f91d1153c?auto=format&fit=crop&w=700&q=80'),
(N'Mercure French Village Bà Nà Hills', N'Đà Nẵng', N'Miền Trung', N'Khu Đỉnh Núi Chúa Làng Pháp Bà Nà, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đỉnh Núi Chúa Làng Pháp Bà Nà, Đà Nẵng.', N'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&w=700&q=80'),
(N'Mikazuki Japanese Onsen Vịnh Đà Nẵng', N'Đà Nẵng', N'Miền Trung', N'Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng, Đà Nẵng', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng, Đà Nẵng.', N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=700&q=80'),
(N'Chạm Mây Boutique Resort & Spa Đà Lạt', N'Đà Lạt', N'Miền Trung', N'Khu Đồi Thông Tinh Mơ - Phường 11, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đồi Thông Tinh Mơ - Phường 11, Đà Lạt.', N'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=700&q=80'),
(N'Ana Mandara French Villas Đồi Lê Lai', N'Đà Lạt', N'Miền Trung', N'Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5, Đà Lạt.', N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=700&q=80'),
(N'Terracotta Pine Peninsula Hồ Tuyền Lâm', N'Đà Lạt', N'Miền Trung', N'Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm, Đà Lạt.', N'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=700&q=80'),
(N'Đồi Chè Cầu Đất Cloud Glamping', N'Đà Lạt', N'Miền Trung', N'Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường, Đà Lạt.', N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=700&q=80'),
(N'Hồ Xuân Hương Heritage Grand Hotel', N'Đà Lạt', N'Miền Trung', N'Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt, Đà Lạt.', N'https://images.unsplash.com/photo-1559599238-308793637427?auto=format&fit=crop&w=700&q=80'),
(N'Thung Lũng Đèn Trại Mát Pine Chalet', N'Đà Lạt', N'Miền Trung', N'Khu Đồi Thông Trại Mát - Dốc Đa Quý, Đà Lạt', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đồi Thông Trại Mát - Dốc Đa Quý, Đà Lạt.', N'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=700&q=80'),
(N'Six Senses Vịnh Ninh Vân Overwater Villa', N'Nha Trang', N'Miền Trung', N'Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân, Nha Trang.', N'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=700&q=80'),
(N'Vinpearl Luxury Đảo Hòn Tre Beachfront', N'Nha Trang', N'Miền Trung', N'Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang, Nha Trang.', N'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=700&q=80'),
(N'The Anam Bãi Dài Cam Ranh Peninsula', N'Nha Trang', N'Miền Trung', N'Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh, Nha Trang.', N'https://images.unsplash.com/photo-1544161515-4ab6ce6db874?auto=format&fit=crop&w=700&q=80'),
(N'Sheraton Trần Phú Ocean Infinity Suites', N'Nha Trang', N'Miền Trung', N'Khu Cung Đường Biển Trần Phú - Quảng Trường, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Cung Đường Biển Trần Phú - Quảng Trường, Nha Trang.', N'https://images.unsplash.com/photo-1576675784201-0e142b423952?auto=format&fit=crop&w=700&q=80'),
(N'Amiana Hòn Chồng Lagoon Pool Resort', N'Nha Trang', N'Miền Trung', N'Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng, Nha Trang.', N'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?auto=format&fit=crop&w=700&q=80'),
(N'I-Resort Vĩnh Ngọc Hot Mineral Villa', N'Nha Trang', N'Miền Trung', N'Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc, Nha Trang', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc, Nha Trang.', N'https://images.unsplash.com/photo-1613490493576-7fde63acd811?auto=format&fit=crop&w=700&q=80'),
(N'Vinpearl Resort & Spa Đảo Rều Hạ Long', N'Hạ Long', N'Miền Bắc', N'Khu Đảo Rều Biệt Lập Bãi Cháy, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đảo Rều Biệt Lập Bãi Cháy, Hạ Long.', N'https://images.unsplash.com/photo-1540202404-a2f29016b523?auto=format&fit=crop&w=700&q=80'),
(N'Yoko Onsen Quang Hanh Valley Villas', N'Hạ Long', N'Miền Bắc', N'Khu Thung Lũng Khoáng Nóng Quang Hanh, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Thung Lũng Khoáng Nóng Quang Hanh, Hạ Long.', N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=700&q=80'),
(N'Tuần Châu Marina Harbor Boutique', N'Hạ Long', N'Miền Bắc', N'Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu, Hạ Long.', N'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=700&q=80'),
(N'FLC Grand Halong Golf & Cliff View', N'Hạ Long', N'Miền Bắc', N'Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai, Hạ Long.', N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=700&q=80'),
(N'Citadines Marina Bán Đảo Hùng Thắng', N'Hạ Long', N'Miền Bắc', N'Khu Bán Đảo Marina Bãi Cháy, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bán Đảo Marina Bãi Cháy, Hạ Long.', N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=700&q=80'),
(N'Vịnh Bái Tử Long Emerald Bay Lodge', N'Hạ Long', N'Miền Bắc', N'Khu Biển Vân Đồn - Vịnh Bái Tử Long, Hạ Long', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Biển Vân Đồn - Vịnh Bái Tử Long, Hạ Long.', N'https://images.unsplash.com/photo-1519046904884-53103b34b206?auto=format&fit=crop&w=700&q=80'),
(N'Meliá Hồ Tràm Beachfront Pool Villas', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=700&q=80'),
(N'The Imperial Victorian Beach Bãi Sau', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Đường Thùy Vân - Bãi Sau Vũng Tàu, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Đường Thùy Vân - Bãi Sau Vũng Tàu, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=700&q=80'),
(N'Mercure Vung Tau Cliffside Bãi Trước', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Mũi Nghinh Phong - Hạ Long Bãi Trước, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Mũi Nghinh Phong - Hạ Long Bãi Trước, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=700&q=80'),
(N'Minera Hot Springs Bình Châu Onsen', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1570129477492-45c003edd2be?auto=format&fit=crop&w=700&q=80'),
(N'Fleur de Lys Resort Đèo Nước Ngọt Long Hải', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Bờ Biển Dinh Cô - Long Hải, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bờ Biển Dinh Cô - Long Hải, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=700&q=80'),
(N'Six Senses Côn Đảo Bãi Đất Dốc', N'Bà Rịa - Vũng Tàu', N'Miền Nam', N'Khu Vịnh Biển Biệt Lập Đảo Côn Đảo, Bà Rịa - Vũng Tàu', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Vịnh Biển Biệt Lập Đảo Côn Đảo, Bà Rịa - Vũng Tàu.', N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=700&q=80'),
(N'Four Seasons The Nam Hải Bãi Biển Hà My', N'Hội An', N'Miền Trung', N'Khu Biệt Thự Biển Hà My - An Bàng, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Biệt Thự Biển Hà My - An Bàng, Hội An.', N'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=700&q=80'),
(N'Anantara Hoi An Sông Thu Bồn Heritage', N'Hội An', N'Miền Trung', N'Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An, Hội An.', N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=700&q=80'),
(N'Làng Rau Trà Quế Organic Field Villa', N'Hội An', N'Miền Trung', N'Khu Cánh Đồng Lúa Làng Rau Trà Quế, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Cánh Đồng Lúa Làng Rau Trà Quế, Hội An.', N'https://images.unsplash.com/photo-1600566753376-12c8ab7fb75b?auto=format&fit=crop&w=700&q=80'),
(N'Victoria Hoi An Beach Resort Cửa Đại', N'Hội An', N'Miền Trung', N'Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm, Hội An.', N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=700&q=80'),
(N'Rừng Dừa Bảy Mẫu Cam Thanh Eco-Lodge', N'Hội An', N'Miền Trung', N'Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh, Hội An.', N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80'),
(N'Làng Lụa Hội An Silk Marina Courtyard', N'Hội An', N'Miền Trung', N'Khu Phố Đèn Lồng Nguyễn Phúc Chu, Hội An', 5, N'Khách sạn & khu nghỉ dưỡng tại Khu Phố Đèn Lồng Nguyễn Phúc Chu, Hội An.', N'https://images.unsplash.com/photo-1556911220-bff31c812dba?auto=format&fit=crop&w=700&q=80');

-- 5.3. Loại phòng (mỗi khách sạn có hạng phòng riêng theo đúng khu vực & mức giá riêng biệt)
INSERT INTO RoomTypes (HotelId, ZoneName, TypeName, Description, PricePerNight, OldPrice, MaxGuests, Area, BedType, ThumbnailUrl) VALUES
(1, N'Phố Đi Bộ Nguyễn Huệ - Quận 1', N'Hạng Phòng Deluxe — Phố Đi Bộ Nguyễn Huệ - Quận 1', N'Không gian nghỉ dưỡng riêng tại Phố Đi Bộ Nguyễn Huệ - Quận 1', 3450000, 4200000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80'),
(2, N'Vinhomes Tân Cảng - Bình Thạnh', N'Hạng Phòng Deluxe — Vinhomes Tân Cảng - Bình Thạnh', N'Không gian nghỉ dưỡng riêng tại Vinhomes Tân Cảng - Bình Thạnh', 2150000, 2750000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=700&q=80'),
(3, N'Biệt Thự Ven Sông Thảo Điền - Quận 2', N'Hạng Phòng Deluxe — Biệt Thự Ven Sông Thảo Điền - Quận 2', N'Không gian nghỉ dưỡng riêng tại Biệt Thự Ven Sông Thảo Điền - Quận 2', 2680000, 3350000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=700&q=80'),
(4, N'Nhà Hát Thành Phố - Công Trường Lam Sơn', N'Hạng Phòng Deluxe — Nhà Hát Thành Phố - Công Trường Lam Sơn', N'Không gian nghỉ dưỡng riêng tại Nhà Hát Thành Phố - Công Trường Lam Sơn', 3190000, 3950000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?auto=format&fit=crop&w=700&q=80'),
(5, N'Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7', N'Hạng Phòng Deluxe — Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7', N'Không gian nghỉ dưỡng riêng tại Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7', 1590000, 2050000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=700&q=80'),
(6, N'Bến Du Thuyền Bạch Đằng - Quận 1', N'Hạng Phòng Deluxe — Bến Du Thuyền Bạch Đằng - Quận 1', N'Không gian nghỉ dưỡng riêng tại Bến Du Thuyền Bạch Đằng - Quận 1', 1820000, 2350000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=700&q=80'),
(7, N'Nhà Hát Lớn & Phố Cổ Hoàn Kiếm', N'Hạng Phòng Deluxe — Nhà Hát Lớn & Phố Cổ Hoàn Kiếm', N'Không gian nghỉ dưỡng riêng tại Nhà Hát Lớn & Phố Cổ Hoàn Kiếm', 2850000, 3500000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=700&q=80'),
(8, N'Mặt Nước Bán Đảo Quảng An - Hồ Tây', N'Hạng Phòng Deluxe — Mặt Nước Bán Đảo Quảng An - Hồ Tây', N'Không gian nghỉ dưỡng riêng tại Mặt Nước Bán Đảo Quảng An - Hồ Tây', 2490000, 3150000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=700&q=80'),
(9, N'Phố Cổ Hàng Trống - Nhà Thờ Lớn', N'Hạng Phòng Deluxe — Phố Cổ Hàng Trống - Nhà Thờ Lớn', N'Không gian nghỉ dưỡng riêng tại Phố Cổ Hàng Trống - Nhà Thờ Lớn', 1890000, 2400000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=700&q=80'),
(10, N'Đào Tấn - Liễu Giai Quận Ba Đình', N'Hạng Phòng Deluxe — Đào Tấn - Liễu Giai Quận Ba Đình', N'Không gian nghỉ dưỡng riêng tại Đào Tấn - Liễu Giai Quận Ba Đình', 2250000, 2890000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1584132967334-10e028bd69f7?auto=format&fit=crop&w=700&q=80'),
(11, N'Sinh Thái Ngoại Ô Sơn Tây - Ba Vì', N'Hạng Phòng Deluxe — Sinh Thái Ngoại Ô Sơn Tây - Ba Vì', N'Không gian nghỉ dưỡng riêng tại Sinh Thái Ngoại Ô Sơn Tây - Ba Vì', 1450000, 1920000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1596394516093-501ba68a0ba6?auto=format&fit=crop&w=700&q=80'),
(12, N'Phố Pháp Tràng Tiền - Hồ Gươm', N'Hạng Phòng Deluxe — Phố Pháp Tràng Tiền - Hồ Gươm', N'Không gian nghỉ dưỡng riêng tại Phố Pháp Tràng Tiền - Hồ Gươm', 1680000, 2180000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=700&q=80'),
(13, N'Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà', N'Hạng Phòng Deluxe — Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà', N'Không gian nghỉ dưỡng riêng tại Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà', 3650000, 4500000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=700&q=80'),
(14, N'Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp', N'Hạng Phòng Deluxe — Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp', N'Không gian nghỉ dưỡng riêng tại Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp', 1650000, 2150000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?auto=format&fit=crop&w=700&q=80'),
(15, N'Bãi Biển Non Nước - Ngũ Hành Sơn', N'Hạng Phòng Deluxe — Bãi Biển Non Nước - Ngũ Hành Sơn', N'Không gian nghỉ dưỡng riêng tại Bãi Biển Non Nước - Ngũ Hành Sơn', 2590000, 3250000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=700&q=80'),
(16, N'Bờ Tây Sông Hàn - Cầu Rồng', N'Hạng Phòng Deluxe — Bờ Tây Sông Hàn - Cầu Rồng', N'Không gian nghỉ dưỡng riêng tại Bờ Tây Sông Hàn - Cầu Rồng', 1920000, 2480000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1568084680786-a84f91d1153c?auto=format&fit=crop&w=700&q=80'),
(17, N'Đỉnh Núi Chúa Làng Pháp Bà Nà', N'Hạng Phòng Deluxe — Đỉnh Núi Chúa Làng Pháp Bà Nà', N'Không gian nghỉ dưỡng riêng tại Đỉnh Núi Chúa Làng Pháp Bà Nà', 2350000, 2990000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&w=700&q=80'),
(18, N'Bãi Biển Xuân Thiều - Vịnh Đà Nẵng', N'Hạng Phòng Deluxe — Bãi Biển Xuân Thiều - Vịnh Đà Nẵng', N'Không gian nghỉ dưỡng riêng tại Bãi Biển Xuân Thiều - Vịnh Đà Nẵng', 2180000, 2750000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=700&q=80'),
(19, N'Đồi Thông Tinh Mơ - Phường 11', N'Hạng Phòng Deluxe — Đồi Thông Tinh Mơ - Phường 11', N'Không gian nghỉ dưỡng riêng tại Đồi Thông Tinh Mơ - Phường 11', 1680000, 2250000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=700&q=80'),
(20, N'Biệt Thự Pháp Cổ Lê Lai - Phường 5', N'Hạng Phòng Deluxe — Biệt Thự Pháp Cổ Lê Lai - Phường 5', N'Không gian nghỉ dưỡng riêng tại Biệt Thự Pháp Cổ Lê Lai - Phường 5', 2490000, 3150000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=700&q=80'),
(21, N'Bán Đảo Rừng Thông Hồ Tuyền Lâm', N'Hạng Phòng Deluxe — Bán Đảo Rừng Thông Hồ Tuyền Lâm', N'Không gian nghỉ dưỡng riêng tại Bán Đảo Rừng Thông Hồ Tuyền Lâm', 1520000, 1980000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=700&q=80'),
(22, N'Săn Mây Đồi Chè Cầu Đất - Xuân Trường', N'Hạng Phòng Deluxe — Săn Mây Đồi Chè Cầu Đất - Xuân Trường', N'Không gian nghỉ dưỡng riêng tại Săn Mây Đồi Chè Cầu Đất - Xuân Trường', 1390000, 1850000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=700&q=80'),
(23, N'Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt', N'Hạng Phòng Deluxe — Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt', N'Không gian nghỉ dưỡng riêng tại Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt', 1850000, 2400000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1559599238-308793637427?auto=format&fit=crop&w=700&q=80'),
(24, N'Đồi Thông Trại Mát - Dốc Đa Quý', N'Hạng Phòng Deluxe — Đồi Thông Trại Mát - Dốc Đa Quý', N'Không gian nghỉ dưỡng riêng tại Đồi Thông Trại Mát - Dốc Đa Quý', 1290000, 1720000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=700&q=80'),
(25, N'Ghềnh Đá Biệt Lập Vịnh Ninh Vân', N'Hạng Phòng Deluxe — Ghềnh Đá Biệt Lập Vịnh Ninh Vân', N'Không gian nghỉ dưỡng riêng tại Ghềnh Đá Biệt Lập Vịnh Ninh Vân', 3750000, 4650000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=700&q=80'),
(26, N'Đảo Riêng Hòn Tre - Vịnh Nha Trang', N'Hạng Phòng Deluxe — Đảo Riêng Hòn Tre - Vịnh Nha Trang', N'Không gian nghỉ dưỡng riêng tại Đảo Riêng Hòn Tre - Vịnh Nha Trang', 2450000, 3100000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=700&q=80'),
(27, N'Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh', N'Hạng Phòng Deluxe — Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh', N'Không gian nghỉ dưỡng riêng tại Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh', 2190000, 2850000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1544161515-4ab6ce6db874?auto=format&fit=crop&w=700&q=80'),
(28, N'Cung Đường Biển Trần Phú - Quảng Trường', N'Hạng Phòng Deluxe — Cung Đường Biển Trần Phú - Quảng Trường', N'Không gian nghỉ dưỡng riêng tại Cung Đường Biển Trần Phú - Quảng Trường', 1780000, 2320000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1576675784201-0e142b423952?auto=format&fit=crop&w=700&q=80'),
(29, N'Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng', N'Hạng Phòng Deluxe — Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng', N'Không gian nghỉ dưỡng riêng tại Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng', 2320000, 2950000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?auto=format&fit=crop&w=700&q=80'),
(30, N'Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc', N'Hạng Phòng Deluxe — Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc', N'Không gian nghỉ dưỡng riêng tại Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc', 1490000, 1950000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1613490493576-7fde63acd811?auto=format&fit=crop&w=700&q=80'),
(31, N'Đảo Rều Biệt Lập Bãi Cháy', N'Hạng Phòng Deluxe — Đảo Rều Biệt Lập Bãi Cháy', N'Không gian nghỉ dưỡng riêng tại Đảo Rều Biệt Lập Bãi Cháy', 2490000, 3200000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1540202404-a2f29016b523?auto=format&fit=crop&w=700&q=80'),
(32, N'Thung Lũng Khoáng Nóng Quang Hanh', N'Hạng Phòng Deluxe — Thung Lũng Khoáng Nóng Quang Hanh', N'Không gian nghỉ dưỡng riêng tại Thung Lũng Khoáng Nóng Quang Hanh', 3150000, 3900000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=700&q=80'),
(33, N'Cảng Du Thuyền Quốc Tế Đảo Tuần Châu', N'Hạng Phòng Deluxe — Cảng Du Thuyền Quốc Tế Đảo Tuần Châu', N'Không gian nghỉ dưỡng riêng tại Cảng Du Thuyền Quốc Tế Đảo Tuần Châu', 1620000, 2100000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=700&q=80'),
(34, N'Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai', N'Hạng Phòng Deluxe — Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai', N'Không gian nghỉ dưỡng riêng tại Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai', 1850000, 2400000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=700&q=80'),
(35, N'Bán Đảo Marina Bãi Cháy', N'Hạng Phòng Deluxe — Bán Đảo Marina Bãi Cháy', N'Không gian nghỉ dưỡng riêng tại Bán Đảo Marina Bãi Cháy', 1540000, 1990000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=700&q=80'),
(36, N'Biển Vân Đồn - Vịnh Bái Tử Long', N'Hạng Phòng Deluxe — Biển Vân Đồn - Vịnh Bái Tử Long', N'Không gian nghỉ dưỡng riêng tại Biển Vân Đồn - Vịnh Bái Tử Long', 1950000, 2550000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1519046904884-53103b34b206?auto=format&fit=crop&w=700&q=80'),
(37, N'Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu', N'Hạng Phòng Deluxe — Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu', N'Không gian nghỉ dưỡng riêng tại Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu', 2690000, 3450000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=700&q=80'),
(38, N'Đường Thùy Vân - Bãi Sau Vũng Tàu', N'Hạng Phòng Deluxe — Đường Thùy Vân - Bãi Sau Vũng Tàu', N'Không gian nghỉ dưỡng riêng tại Đường Thùy Vân - Bãi Sau Vũng Tàu', 1950000, 2500000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=700&q=80'),
(39, N'Mũi Nghinh Phong - Hạ Long Bãi Trước', N'Hạng Phòng Deluxe — Mũi Nghinh Phong - Hạ Long Bãi Trước', N'Không gian nghỉ dưỡng riêng tại Mũi Nghinh Phong - Hạ Long Bãi Trước', 1780000, 2320000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=700&q=80'),
(40, N'Rừng Khoáng Nóng Bình Châu - Xuyên Mộc', N'Hạng Phòng Deluxe — Rừng Khoáng Nóng Bình Châu - Xuyên Mộc', N'Không gian nghỉ dưỡng riêng tại Rừng Khoáng Nóng Bình Châu - Xuyên Mộc', 2250000, 2900000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1570129477492-45c003edd2be?auto=format&fit=crop&w=700&q=80'),
(41, N'Bờ Biển Dinh Cô - Long Hải', N'Hạng Phòng Deluxe — Bờ Biển Dinh Cô - Long Hải', N'Không gian nghỉ dưỡng riêng tại Bờ Biển Dinh Cô - Long Hải', 1590000, 2100000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=700&q=80'),
(42, N'Vịnh Biển Biệt Lập Đảo Côn Đảo', N'Hạng Phòng Deluxe — Vịnh Biển Biệt Lập Đảo Côn Đảo', N'Không gian nghỉ dưỡng riêng tại Vịnh Biển Biệt Lập Đảo Côn Đảo', 3850000, 4800000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=700&q=80'),
(43, N'Biệt Thự Biển Hà My - An Bàng', N'Hạng Phòng Deluxe — Biệt Thự Biển Hà My - An Bàng', N'Không gian nghỉ dưỡng riêng tại Biệt Thự Biển Hà My - An Bàng', 3550000, 4450000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=700&q=80'),
(44, N'Bến Thuyền Sông Hoài - Phố Cổ Hội An', N'Hạng Phòng Deluxe — Bến Thuyền Sông Hoài - Phố Cổ Hội An', N'Không gian nghỉ dưỡng riêng tại Bến Thuyền Sông Hoài - Phố Cổ Hội An', 2390000, 3050000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=700&q=80'),
(45, N'Cánh Đồng Lúa Làng Rau Trà Quế', N'Hạng Phòng Deluxe — Cánh Đồng Lúa Làng Rau Trà Quế', N'Không gian nghỉ dưỡng riêng tại Cánh Đồng Lúa Làng Rau Trà Quế', 1480000, 1950000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1600566753376-12c8ab7fb75b?auto=format&fit=crop&w=700&q=80'),
(46, N'Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm', N'Hạng Phòng Deluxe — Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm', N'Không gian nghỉ dưỡng riêng tại Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm', 1890000, 2450000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=700&q=80'),
(47, N'Sinh Thái Rừng Dừa Nước Cẩm Thanh', N'Hạng Phòng Deluxe — Sinh Thái Rừng Dừa Nước Cẩm Thanh', N'Không gian nghỉ dưỡng riêng tại Sinh Thái Rừng Dừa Nước Cẩm Thanh', 1350000, 1800000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80'),
(48, N'Phố Đèn Lồng Nguyễn Phúc Chu', N'Hạng Phòng Deluxe — Phố Đèn Lồng Nguyễn Phúc Chu', N'Không gian nghỉ dưỡng riêng tại Phố Đèn Lồng Nguyễn Phúc Chu', 1690000, 2200000, 2, 42, N'1 giường King', N'https://images.unsplash.com/photo-1556911220-bff31c812dba?auto=format&fit=crop&w=700&q=80');

-- 5.4. Bộ 4 ảnh riêng biệt cho từng loại phòng / từng khu vực (RoomTypeImages)
INSERT INTO RoomTypeImages (RoomTypeId, ImageUrl, Caption, SortOrder) VALUES
(1, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80', N'Khu Phố Đi Bộ Nguyễn Huệ - Quận 1 — Không gian tổng quan', 1),
(1, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1011', N'Khu Phố Đi Bộ Nguyễn Huệ - Quận 1 — Phòng ngủ chính & ban công', 2),
(1, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1012', N'Khu Phố Đi Bộ Nguyễn Huệ - Quận 1 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(1, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1013', N'Khu Phố Đi Bộ Nguyễn Huệ - Quận 1 — Phòng tắm & tiện nghi cao cấp', 4),
(2, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=700&q=80', N'Khu Vinhomes Tân Cảng - Bình Thạnh — Không gian tổng quan', 1),
(2, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1021', N'Khu Vinhomes Tân Cảng - Bình Thạnh — Phòng ngủ chính & ban công', 2),
(2, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1022', N'Khu Vinhomes Tân Cảng - Bình Thạnh — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(2, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1023', N'Khu Vinhomes Tân Cảng - Bình Thạnh — Phòng tắm & tiện nghi cao cấp', 4),
(3, N'https://images.unsplash.com/photo-1542314831-068cd1dbfeeb?auto=format&fit=crop&w=700&q=80', N'Khu Biệt Thự Ven Sông Thảo Điền - Quận 2 — Không gian tổng quan', 1),
(3, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1031', N'Khu Biệt Thự Ven Sông Thảo Điền - Quận 2 — Phòng ngủ chính & ban công', 2),
(3, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1032', N'Khu Biệt Thự Ven Sông Thảo Điền - Quận 2 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(3, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1033', N'Khu Biệt Thự Ven Sông Thảo Điền - Quận 2 — Phòng tắm & tiện nghi cao cấp', 4),
(4, N'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?auto=format&fit=crop&w=700&q=80', N'Khu Nhà Hát Thành Phố - Công Trường Lam Sơn — Không gian tổng quan', 1),
(4, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1041', N'Khu Nhà Hát Thành Phố - Công Trường Lam Sơn — Phòng ngủ chính & ban công', 2),
(4, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1042', N'Khu Nhà Hát Thành Phố - Công Trường Lam Sơn — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(4, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1043', N'Khu Nhà Hát Thành Phố - Công Trường Lam Sơn — Phòng tắm & tiện nghi cao cấp', 4),
(5, N'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=700&q=80', N'Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7 — Không gian tổng quan', 1),
(5, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1051', N'Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7 — Phòng ngủ chính & ban công', 2),
(5, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1052', N'Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(5, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1053', N'Khu Hồ Bán Nguyệt Phú Mỹ Hưng - Quận 7 — Phòng tắm & tiện nghi cao cấp', 4),
(6, N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=700&q=80', N'Khu Bến Du Thuyền Bạch Đằng - Quận 1 — Không gian tổng quan', 1),
(6, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1061', N'Khu Bến Du Thuyền Bạch Đằng - Quận 1 — Phòng ngủ chính & ban công', 2),
(6, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1062', N'Khu Bến Du Thuyền Bạch Đằng - Quận 1 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(6, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1063', N'Khu Bến Du Thuyền Bạch Đằng - Quận 1 — Phòng tắm & tiện nghi cao cấp', 4),
(7, N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=700&q=80', N'Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm — Không gian tổng quan', 1),
(7, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1071', N'Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm — Phòng ngủ chính & ban công', 2),
(7, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1072', N'Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(7, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1073', N'Khu Nhà Hát Lớn & Phố Cổ Hoàn Kiếm — Phòng tắm & tiện nghi cao cấp', 4),
(8, N'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=700&q=80', N'Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây — Không gian tổng quan', 1),
(8, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1081', N'Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây — Phòng ngủ chính & ban công', 2),
(8, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1082', N'Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(8, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1083', N'Khu Mặt Nước Bán Đảo Quảng An - Hồ Tây — Phòng tắm & tiện nghi cao cấp', 4),
(9, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=700&q=80', N'Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn — Không gian tổng quan', 1),
(9, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1091', N'Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn — Phòng ngủ chính & ban công', 2),
(9, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1092', N'Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(9, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1093', N'Khu Phố Cổ Hàng Trống - Nhà Thờ Lớn — Phòng tắm & tiện nghi cao cấp', 4),
(10, N'https://images.unsplash.com/photo-1584132967334-10e028bd69f7?auto=format&fit=crop&w=700&q=80', N'Khu Đào Tấn - Liễu Giai Quận Ba Đình — Không gian tổng quan', 1),
(10, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1101', N'Khu Đào Tấn - Liễu Giai Quận Ba Đình — Phòng ngủ chính & ban công', 2),
(10, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1102', N'Khu Đào Tấn - Liễu Giai Quận Ba Đình — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(10, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1103', N'Khu Đào Tấn - Liễu Giai Quận Ba Đình — Phòng tắm & tiện nghi cao cấp', 4),
(11, N'https://images.unsplash.com/photo-1596394516093-501ba68a0ba6?auto=format&fit=crop&w=700&q=80', N'Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì — Không gian tổng quan', 1),
(11, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1111', N'Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì — Phòng ngủ chính & ban công', 2),
(11, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1112', N'Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(11, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1113', N'Khu Sinh Thái Ngoại Ô Sơn Tây - Ba Vì — Phòng tắm & tiện nghi cao cấp', 4),
(12, N'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=700&q=80', N'Khu Phố Pháp Tràng Tiền - Hồ Gươm — Không gian tổng quan', 1),
(12, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1121', N'Khu Phố Pháp Tràng Tiền - Hồ Gươm — Phòng ngủ chính & ban công', 2),
(12, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1122', N'Khu Phố Pháp Tràng Tiền - Hồ Gươm — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(12, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1123', N'Khu Phố Pháp Tràng Tiền - Hồ Gươm — Phòng tắm & tiện nghi cao cấp', 4),
(13, N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=700&q=80', N'Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà — Không gian tổng quan', 1),
(13, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1131', N'Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà — Phòng ngủ chính & ban công', 2),
(13, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1132', N'Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(13, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1133', N'Khu Ghềnh Đá Bãi Bắc Bán Đảo Sơn Trà — Phòng tắm & tiện nghi cao cấp', 4),
(14, N'https://images.unsplash.com/photo-1571003123894-1f0594d2b5d9?auto=format&fit=crop&w=700&q=80', N'Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp — Không gian tổng quan', 1),
(14, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1141', N'Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp — Phòng ngủ chính & ban công', 2),
(14, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1142', N'Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(14, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1143', N'Khu Bãi Biển Mỹ Khê - Đường Võ Nguyên Giáp — Phòng tắm & tiện nghi cao cấp', 4),
(15, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=700&q=80', N'Khu Bãi Biển Non Nước - Ngũ Hành Sơn — Không gian tổng quan', 1),
(15, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1151', N'Khu Bãi Biển Non Nước - Ngũ Hành Sơn — Phòng ngủ chính & ban công', 2),
(15, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1152', N'Khu Bãi Biển Non Nước - Ngũ Hành Sơn — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(15, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1153', N'Khu Bãi Biển Non Nước - Ngũ Hành Sơn — Phòng tắm & tiện nghi cao cấp', 4),
(16, N'https://images.unsplash.com/photo-1568084680786-a84f91d1153c?auto=format&fit=crop&w=700&q=80', N'Khu Bờ Tây Sông Hàn - Cầu Rồng — Không gian tổng quan', 1),
(16, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1161', N'Khu Bờ Tây Sông Hàn - Cầu Rồng — Phòng ngủ chính & ban công', 2),
(16, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1162', N'Khu Bờ Tây Sông Hàn - Cầu Rồng — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(16, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1163', N'Khu Bờ Tây Sông Hàn - Cầu Rồng — Phòng tắm & tiện nghi cao cấp', 4),
(17, N'https://images.unsplash.com/photo-1520250497591-112f2f40a3f4?auto=format&fit=crop&w=700&q=80', N'Khu Đỉnh Núi Chúa Làng Pháp Bà Nà — Không gian tổng quan', 1),
(17, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1171', N'Khu Đỉnh Núi Chúa Làng Pháp Bà Nà — Phòng ngủ chính & ban công', 2),
(17, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1172', N'Khu Đỉnh Núi Chúa Làng Pháp Bà Nà — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(17, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1173', N'Khu Đỉnh Núi Chúa Làng Pháp Bà Nà — Phòng tắm & tiện nghi cao cấp', 4),
(18, N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=700&q=80', N'Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng — Không gian tổng quan', 1),
(18, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1181', N'Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng — Phòng ngủ chính & ban công', 2),
(18, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1182', N'Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(18, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1183', N'Khu Bãi Biển Xuân Thiều - Vịnh Đà Nẵng — Phòng tắm & tiện nghi cao cấp', 4),
(19, N'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=700&q=80', N'Khu Đồi Thông Tinh Mơ - Phường 11 — Không gian tổng quan', 1),
(19, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1191', N'Khu Đồi Thông Tinh Mơ - Phường 11 — Phòng ngủ chính & ban công', 2),
(19, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1192', N'Khu Đồi Thông Tinh Mơ - Phường 11 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(19, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1193', N'Khu Đồi Thông Tinh Mơ - Phường 11 — Phòng tắm & tiện nghi cao cấp', 4),
(20, N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=700&q=80', N'Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5 — Không gian tổng quan', 1),
(20, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1201', N'Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5 — Phòng ngủ chính & ban công', 2),
(20, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1202', N'Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5 — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(20, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1203', N'Khu Biệt Thự Pháp Cổ Lê Lai - Phường 5 — Phòng tắm & tiện nghi cao cấp', 4),
(21, N'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=700&q=80', N'Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm — Không gian tổng quan', 1),
(21, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1211', N'Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm — Phòng ngủ chính & ban công', 2),
(21, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1212', N'Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(21, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1213', N'Khu Bán Đảo Rừng Thông Hồ Tuyền Lâm — Phòng tắm & tiện nghi cao cấp', 4),
(22, N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=700&q=80', N'Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường — Không gian tổng quan', 1),
(22, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1221', N'Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường — Phòng ngủ chính & ban công', 2),
(22, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1222', N'Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(22, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1223', N'Khu Săn Mây Đồi Chè Cầu Đất - Xuân Trường — Phòng tắm & tiện nghi cao cấp', 4),
(23, N'https://images.unsplash.com/photo-1559599238-308793637427?auto=format&fit=crop&w=700&q=80', N'Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt — Không gian tổng quan', 1),
(23, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1231', N'Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt — Phòng ngủ chính & ban công', 2),
(23, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1232', N'Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(23, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1233', N'Khu Trung Tâm Hồ Xuân Hương - Chợ Đà Lạt — Phòng tắm & tiện nghi cao cấp', 4),
(24, N'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=700&q=80', N'Khu Đồi Thông Trại Mát - Dốc Đa Quý — Không gian tổng quan', 1),
(24, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1241', N'Khu Đồi Thông Trại Mát - Dốc Đa Quý — Phòng ngủ chính & ban công', 2),
(24, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1242', N'Khu Đồi Thông Trại Mát - Dốc Đa Quý — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(24, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1243', N'Khu Đồi Thông Trại Mát - Dốc Đa Quý — Phòng tắm & tiện nghi cao cấp', 4),
(25, N'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=700&q=80', N'Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân — Không gian tổng quan', 1),
(25, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1251', N'Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân — Phòng ngủ chính & ban công', 2),
(25, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1252', N'Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(25, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1253', N'Khu Ghềnh Đá Biệt Lập Vịnh Ninh Vân — Phòng tắm & tiện nghi cao cấp', 4),
(26, N'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=700&q=80', N'Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang — Không gian tổng quan', 1),
(26, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1261', N'Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang — Phòng ngủ chính & ban công', 2),
(26, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1262', N'Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(26, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1263', N'Khu Đảo Riêng Hòn Tre - Vịnh Nha Trang — Phòng tắm & tiện nghi cao cấp', 4),
(27, N'https://images.unsplash.com/photo-1544161515-4ab6ce6db874?auto=format&fit=crop&w=700&q=80', N'Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh — Không gian tổng quan', 1),
(27, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1271', N'Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh — Phòng ngủ chính & ban công', 2),
(27, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1272', N'Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(27, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1273', N'Khu Bờ Biển Bãi Dài Bắc Bán Đảo Cam Ranh — Phòng tắm & tiện nghi cao cấp', 4),
(28, N'https://images.unsplash.com/photo-1576675784201-0e142b423952?auto=format&fit=crop&w=700&q=80', N'Khu Cung Đường Biển Trần Phú - Quảng Trường — Không gian tổng quan', 1),
(28, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1281', N'Khu Cung Đường Biển Trần Phú - Quảng Trường — Phòng ngủ chính & ban công', 2),
(28, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1282', N'Khu Cung Đường Biển Trần Phú - Quảng Trường — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(28, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1283', N'Khu Cung Đường Biển Trần Phú - Quảng Trường — Phòng tắm & tiện nghi cao cấp', 4),
(29, N'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?auto=format&fit=crop&w=700&q=80', N'Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng — Không gian tổng quan', 1),
(29, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1291', N'Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng — Phòng ngủ chính & ban công', 2),
(29, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1292', N'Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(29, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1293', N'Khu Bến Du Thuyền Phạm Văn Đồng - Hòn Chồng — Phòng tắm & tiện nghi cao cấp', 4),
(30, N'https://images.unsplash.com/photo-1613490493576-7fde63acd811?auto=format&fit=crop&w=700&q=80', N'Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc — Không gian tổng quan', 1),
(30, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1301', N'Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc — Phòng ngủ chính & ban công', 2),
(30, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1302', N'Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(30, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1303', N'Khu Suối Khoáng Nóng Tháp Bà - Vĩnh Ngọc — Phòng tắm & tiện nghi cao cấp', 4),
(31, N'https://images.unsplash.com/photo-1540202404-a2f29016b523?auto=format&fit=crop&w=700&q=80', N'Khu Đảo Rều Biệt Lập Bãi Cháy — Không gian tổng quan', 1),
(31, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1311', N'Khu Đảo Rều Biệt Lập Bãi Cháy — Phòng ngủ chính & ban công', 2),
(31, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1312', N'Khu Đảo Rều Biệt Lập Bãi Cháy — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(31, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1313', N'Khu Đảo Rều Biệt Lập Bãi Cháy — Phòng tắm & tiện nghi cao cấp', 4),
(32, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=700&q=80', N'Khu Thung Lũng Khoáng Nóng Quang Hanh — Không gian tổng quan', 1),
(32, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1321', N'Khu Thung Lũng Khoáng Nóng Quang Hanh — Phòng ngủ chính & ban công', 2),
(32, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1322', N'Khu Thung Lũng Khoáng Nóng Quang Hanh — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(32, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1323', N'Khu Thung Lũng Khoáng Nóng Quang Hanh — Phòng tắm & tiện nghi cao cấp', 4),
(33, N'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=700&q=80', N'Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu — Không gian tổng quan', 1),
(33, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1331', N'Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu — Phòng ngủ chính & ban công', 2),
(33, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1332', N'Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(33, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1333', N'Khu Cảng Du Thuyền Quốc Tế Đảo Tuần Châu — Phòng tắm & tiện nghi cao cấp', 4),
(34, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=700&q=80', N'Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai — Không gian tổng quan', 1),
(34, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1341', N'Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai — Phòng ngủ chính & ban công', 2),
(34, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1342', N'Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(34, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1343', N'Khu Đồi Văn Nghệ Cột 3 - Cột 8 Hòn Gai — Phòng tắm & tiện nghi cao cấp', 4),
(35, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=700&q=80', N'Khu Bán Đảo Marina Bãi Cháy — Không gian tổng quan', 1),
(35, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1351', N'Khu Bán Đảo Marina Bãi Cháy — Phòng ngủ chính & ban công', 2),
(35, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1352', N'Khu Bán Đảo Marina Bãi Cháy — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(35, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1353', N'Khu Bán Đảo Marina Bãi Cháy — Phòng tắm & tiện nghi cao cấp', 4),
(36, N'https://images.unsplash.com/photo-1519046904884-53103b34b206?auto=format&fit=crop&w=700&q=80', N'Khu Biển Vân Đồn - Vịnh Bái Tử Long — Không gian tổng quan', 1),
(36, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1361', N'Khu Biển Vân Đồn - Vịnh Bái Tử Long — Phòng ngủ chính & ban công', 2),
(36, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1362', N'Khu Biển Vân Đồn - Vịnh Bái Tử Long — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(36, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1363', N'Khu Biển Vân Đồn - Vịnh Bái Tử Long — Phòng tắm & tiện nghi cao cấp', 4),
(37, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=700&q=80', N'Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu — Không gian tổng quan', 1),
(37, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1371', N'Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu — Phòng ngủ chính & ban công', 2),
(37, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1372', N'Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(37, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1373', N'Khu Biển Hồ Tràm - Rừng Nguyên Sinh Phước Bửu — Phòng tắm & tiện nghi cao cấp', 4),
(38, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=700&q=80', N'Khu Đường Thùy Vân - Bãi Sau Vũng Tàu — Không gian tổng quan', 1),
(38, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1381', N'Khu Đường Thùy Vân - Bãi Sau Vũng Tàu — Phòng ngủ chính & ban công', 2),
(38, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1382', N'Khu Đường Thùy Vân - Bãi Sau Vũng Tàu — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(38, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1383', N'Khu Đường Thùy Vân - Bãi Sau Vũng Tàu — Phòng tắm & tiện nghi cao cấp', 4),
(39, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=700&q=80', N'Khu Mũi Nghinh Phong - Hạ Long Bãi Trước — Không gian tổng quan', 1),
(39, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1391', N'Khu Mũi Nghinh Phong - Hạ Long Bãi Trước — Phòng ngủ chính & ban công', 2),
(39, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1392', N'Khu Mũi Nghinh Phong - Hạ Long Bãi Trước — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(39, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1393', N'Khu Mũi Nghinh Phong - Hạ Long Bãi Trước — Phòng tắm & tiện nghi cao cấp', 4),
(40, N'https://images.unsplash.com/photo-1570129477492-45c003edd2be?auto=format&fit=crop&w=700&q=80', N'Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc — Không gian tổng quan', 1),
(40, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1401', N'Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc — Phòng ngủ chính & ban công', 2),
(40, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1402', N'Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(40, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1403', N'Khu Rừng Khoáng Nóng Bình Châu - Xuyên Mộc — Phòng tắm & tiện nghi cao cấp', 4),
(41, N'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?auto=format&fit=crop&w=700&q=80', N'Khu Bờ Biển Dinh Cô - Long Hải — Không gian tổng quan', 1),
(41, N'https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=800&q=80&sig=1411', N'Khu Bờ Biển Dinh Cô - Long Hải — Phòng ngủ chính & ban công', 2),
(41, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1412', N'Khu Bờ Biển Dinh Cô - Long Hải — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(41, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1413', N'Khu Bờ Biển Dinh Cô - Long Hải — Phòng tắm & tiện nghi cao cấp', 4),
(42, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=700&q=80', N'Khu Vịnh Biển Biệt Lập Đảo Côn Đảo — Không gian tổng quan', 1),
(42, N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80&sig=1421', N'Khu Vịnh Biển Biệt Lập Đảo Côn Đảo — Phòng ngủ chính & ban công', 2),
(42, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1422', N'Khu Vịnh Biển Biệt Lập Đảo Côn Đảo — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(42, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1423', N'Khu Vịnh Biển Biệt Lập Đảo Côn Đảo — Phòng tắm & tiện nghi cao cấp', 4),
(43, N'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=700&q=80', N'Khu Biệt Thự Biển Hà My - An Bàng — Không gian tổng quan', 1),
(43, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80&sig=1431', N'Khu Biệt Thự Biển Hà My - An Bàng — Phòng ngủ chính & ban công', 2),
(43, N'https://images.unsplash.com/photo-1560185007-cde436f6a4d0?auto=format&fit=crop&w=800&q=80&sig=1432', N'Khu Biệt Thự Biển Hà My - An Bàng — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(43, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1433', N'Khu Biệt Thự Biển Hà My - An Bàng — Phòng tắm & tiện nghi cao cấp', 4),
(44, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=700&q=80', N'Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An — Không gian tổng quan', 1),
(44, N'https://images.unsplash.com/photo-1618773928121-c32242e63f39?auto=format&fit=crop&w=800&q=80&sig=1441', N'Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An — Phòng ngủ chính & ban công', 2),
(44, N'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=800&q=80&sig=1442', N'Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(44, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1443', N'Khu Bến Thuyền Sông Hoài - Phố Cổ Hội An — Phòng tắm & tiện nghi cao cấp', 4),
(45, N'https://images.unsplash.com/photo-1600566753376-12c8ab7fb75b?auto=format&fit=crop&w=700&q=80', N'Khu Cánh Đồng Lúa Làng Rau Trà Quế — Không gian tổng quan', 1),
(45, N'https://images.unsplash.com/photo-1598928506311-c55ded91a20c?auto=format&fit=crop&w=800&q=80&sig=1451', N'Khu Cánh Đồng Lúa Làng Rau Trà Quế — Phòng ngủ chính & ban công', 2),
(45, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=800&q=80&sig=1452', N'Khu Cánh Đồng Lúa Làng Rau Trà Quế — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(45, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1453', N'Khu Cánh Đồng Lúa Làng Rau Trà Quế — Phòng tắm & tiện nghi cao cấp', 4),
(46, N'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=700&q=80', N'Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm — Không gian tổng quan', 1),
(46, N'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?auto=format&fit=crop&w=800&q=80&sig=1461', N'Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm — Phòng ngủ chính & ban công', 2),
(46, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80&sig=1462', N'Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(46, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1463', N'Khu Bãi Biển Cửa Đại - Bến Tàu Cù Lao Chàm — Phòng tắm & tiện nghi cao cấp', 4),
(47, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=700&q=80', N'Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh — Không gian tổng quan', 1),
(47, N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80&sig=1471', N'Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh — Phòng ngủ chính & ban công', 2),
(47, N'https://images.unsplash.com/photo-1507652313519-d4e9174996dd?auto=format&fit=crop&w=800&q=80&sig=1472', N'Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(47, N'https://images.unsplash.com/photo-1566665797739-1674de7a421a?auto=format&fit=crop&w=800&q=80&sig=1473', N'Khu Sinh Thái Rừng Dừa Nước Cẩm Thanh — Phòng tắm & tiện nghi cao cấp', 4),
(48, N'https://images.unsplash.com/photo-1556911220-bff31c812dba?auto=format&fit=crop&w=700&q=80', N'Khu Phố Đèn Lồng Nguyễn Phúc Chu — Không gian tổng quan', 1),
(48, N'https://images.unsplash.com/photo-1552321554-5fefe8c9ef14?auto=format&fit=crop&w=800&q=80&sig=1481', N'Khu Phố Đèn Lồng Nguyễn Phúc Chu — Phòng ngủ chính & ban công', 2),
(48, N'https://images.unsplash.com/photo-1591088398332-8a7791972843?auto=format&fit=crop&w=800&q=80&sig=1482', N'Khu Phố Đèn Lồng Nguyễn Phúc Chu — Hồ bơi & sân hiên nghỉ dưỡng', 3),
(48, N'https://images.unsplash.com/photo-1595576508898-0ad5c879a061?auto=format&fit=crop&w=800&q=80&sig=1483', N'Khu Phố Đèn Lồng Nguyễn Phúc Chu — Phòng tắm & tiện nghi cao cấp', 4);

-- 5.5. Phòng vật lý (mỗi hạng phòng 2 phòng 101, 102)
INSERT INTO Rooms (RoomTypeId, RoomNumber, Floor, IsActive)
SELECT rt.RoomTypeId, n.RoomNumber, 1, 1
FROM RoomTypes rt
CROSS JOIN (VALUES (N'101'), (N'102')) n(RoomNumber)
ORDER BY rt.RoomTypeId, n.RoomNumber;

-- 5.6. Tiện nghi
INSERT INTO Amenities (AmenityName, Category) VALUES
(N'Wi-Fi miễn phí trong tất cả các phòng', N'Internet'),
(N'Internet cáp quang tốc độ cao',         N'Internet'),
(N'Hồ bơi vô cực nước ấm 4 mùa',           N'Thư giãn'),
(N'Khu tắm khoáng nóng Onsen & Spa',       N'Thư giãn'),
(N'Sân vườn dạo bộ riêng biệt',            N'Thư giãn'),
(N'Hỗ trợ y tế trực 24/7',                 N'An toàn'),
(N'Khử trùng phòng tiêu chuẩn trước nhận', N'An toàn'),
(N'Hệ thống báo khói & an ninh 24h',       N'An toàn'),
(N'Quầy lễ tân phục vụ 24 giờ',            N'Dịch vụ'),
(N'Dịch vụ xe đưa đón sân bay tận nơi',    N'Dịch vụ'),
(N'Dọn phòng hằng ngày miễn phí',          N'Dịch vụ'),
(N'Bữa sáng miễn phí',                     N'Dịch vụ'),
(N'Ấm đun nước & Máy pha cà phê',          N'Trong phòng'),
(N'Kính cách âm 2 lớp & Rèm cản sáng',     N'Trong phòng'),
(N'Điều hòa 2 chiều & Hệ thống sưởi',      N'Trong phòng'),
(N'Bồn tắm riêng & Áo choàng tắm',         N'Trong phòng'),
(N'Smart TV 55 inch & Bàn làm việc',       N'Trong phòng');

INSERT INTO RoomTypeAmenities (RoomTypeId, AmenityId)
SELECT rt.RoomTypeId, a.AmenityId
FROM RoomTypes rt
CROSS JOIN Amenities a;

-- 5.7. 7 Mã giảm giá (khớp dải 7 thẻ vé đục lỗ kéo ngang trên Trang chủ)
INSERT INTO Coupons (Code, Title, DiscountType, DiscountValue, MaxDiscount, MinOrderAmount,
                     MinLoyaltyPoints, IsNewUserOnly, StartDate, EndDate) VALUES
(N'CHAMBANMOI',    N'Giảm tới 250.000đ cho lần đặt phòng đầu tiên',          N'Fixed',   250000, NULL,   1200000,   0, 1, '2026-01-01', '2026-12-31'),
(N'CHAMLUX15',     N'Giảm đến 15% (tối đa 500K) Resort & Villa 5 sao',       N'Percent', 15,     500000, 2000000, 100, 0, '2026-01-01', '2026-12-31'),
(N'CHAMBAY75',     N'Giảm đến 75.000đ cho lần đặt vé máy bay đầu tiên',      N'Fixed',   75000,  NULL,   1000000,   0, 1, '2026-01-01', '2026-12-31'),
(N'CHAMSANBAY',    N'Giảm 100.000đ khi đặt xe đưa đón sân bay 2 chiều',      N'Fixed',   100000, NULL,    800000,   0, 0, '2026-01-01', '2026-12-31'),
(N'CHAMMIENTRUNG', N'Giảm ngay 300.000đ kỳ nghỉ Đà Nẵng - Hội An - Đà Lạt',  N'Fixed',   300000, NULL,   1800000,   0, 0, '2026-01-01', '2026-12-31'),
(N'CHAMSOM20',     N'Ưu đãi đặt sớm trước 14 ngày: Giảm thêm 20%',           N'Percent', 20,     600000, 1500000,   0, 0, '2026-01-01', '2026-12-31'),
(N'CHAMMOMO120',   N'Giảm thêm 120.000đ khi thanh toán qua Ví MoMo / VietQR',N'Fixed',   120000, NULL,   1500000,   0, 0, '2026-01-01', '2026-12-31');

-- 5.8. Đơn đặt phòng mẫu
INSERT INTO Bookings (UserId, CouponId, DiscountAmount, CheckInDate, CheckOutDate, Status, CreatedAt) VALUES
(2, 1, 250000, '2026-11-10', '2026-11-12', N'Confirmed', '2026-11-01'),
(3, 2, 500000, '2026-11-12', '2026-11-14', N'Confirmed', '2026-11-03'),
(4, NULL,   0, '2026-11-15', '2026-11-17', N'Confirmed', '2026-11-05'),
(5, 5, 300000, '2026-12-12', '2026-12-13', N'Pending',   '2026-11-10'),
(6, 7, 120000, '2026-10-20', '2026-10-22', N'Confirmed', '2026-10-15');

INSERT INTO BookingDetails (BookingId, RoomId, UnitPrice)
SELECT v.BookingId, r.RoomId, rt.PricePerNight
FROM (VALUES
    (1, 19, N'101'),   -- Chạm Mây Boutique Resort & Spa Đà Lạt
    (2, 1,  N'101'),   -- The Reverie Saigon Đồng Khởi
    (3, 7,  N'101'),   -- Capella Hanoi Opera Heritage
    (4, 13, N'101'),   -- InterContinental Sun Peninsula Sơn Trà
    (5, 37, N'101')    -- Meliá Hồ Tràm Beachfront Pool Villas
) v(BookingId, HotelId, RoomNumber)
INNER JOIN RoomTypes rt ON rt.HotelId = v.HotelId
INNER JOIN Rooms r      ON r.RoomTypeId = rt.RoomTypeId AND r.RoomNumber = v.RoomNumber;

UPDATE Bookings SET Status = N'Completed' WHERE BookingId IN (1, 2, 3, 5);

-- 5.9. Thanh toán (4 phương thức: MoMo, VietQR, Card, Cash)
INSERT INTO Payments (BookingId, PaymentMethod, Amount, PaymentDate, Status, TransactionCode) VALUES
(1, N'MoMo',   3110000, '2026-11-10', N'Completed', N'MOMO-20261110-0001'),
(2, N'Card',   6400000, '2026-11-12', N'Completed', N'CARD-20261112-0002'),
(3, N'VietQR', 5700000, '2026-11-15', N'Completed', N'VQR-20261115-0003'),
(4, N'Cash',   3350000, '2026-12-12', N'Pending',   NULL),
(5, N'MoMo',   5260000, '2026-10-20', N'Completed', N'MOMO-20261020-0005');

-- 5.10. Đánh giá từ khách thật (Reviews)
INSERT INTO Reviews (UserId, RoomTypeId, BookingId, Rating, CleanlinessScore, LocationScore,
                     ServiceScore, FacilitiesScore, ValueForMoneyScore, Title, Comment, CreatedAt) VALUES
(2, 19, 1, 9.8, 10, 10, 10, 9, 9, N'Sáng mở rèm ra là biển mây tràn vào tận hiên gỗ!',
    N'Phòng cực kỳ ấm cúng, có lò sưởi củi thông thơm dịu và bồn tắm đá ngâm thảo mộc. Xe đưa đón sân bay Liên Khương đúng giờ.', '2026-11-12'),
(3, 1,  2, 9.6, 10, 10,  9, 9, 9, N'Phòng sang trọng ngay phố đi bộ Nguyễn Huệ',
    N'Tầm nhìn toàn cảnh trung tâm Quận 1 và sông Sài Gòn tuyệt đẹp, buffet sáng đa dạng.', '2026-11-14'),
(4, 7,  3, 9.5,  9, 10, 10, 9, 9, N'Kiến trúc di sản cạnh Nhà Hát Lớn Hà Nội',
    N'Đi bộ vài bước là ra Hồ Hoàn Kiếm và phố Tràng Tiền, nhân viên lễ tân hỗ trợ 24/7 rất chu đáo.', '2026-11-17'),
(6, 37, 5, 9.4, 10,  9,  9, 9, 9, N'Biệt thự biển Hồ Tràm có hồ bơi riêng rất chill',
    N'Áp mã CHAMMOMO120 tiết kiệm thêm khi thanh toán qua ví điện tử. Không gian biển và rừng nguyên sinh rất trong lành.', '2026-10-23');
GO

-- =====================================================================
-- 6. KIỂM TRA NHANH
-- =====================================================================
SELECT UserId, FullName, Role, LoyaltyPoints FROM Users;
SELECT BookingId, UserId, CouponId, Status, SubTotal, DiscountAmount, TotalAmount FROM Bookings ORDER BY BookingId;
SELECT * FROM vw_HotelRatingSummary ORDER BY City, HotelId;
SELECT COUNT(*) AS SoBang FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';
