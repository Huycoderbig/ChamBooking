-- =====================================================================
-- TỔNG QUAN FILE: Database/HotelBookingDB_v3.sql
-- - File này làm gì: Tạo CSDL cho website đặt phòng "Chạm" - bản 12 bảng
--   gọn cho demo (nhiều khách sạn, 20 điểm đến, phân khu, ảnh phòng,
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
CREATE TABLE RoomTypeAmenities (
    RoomTypeId int NOT NULL,
    AmenityId  int NOT NULL,
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
-- 5. DỮ LIỆU MẪU
-- =====================================================================

-- 5.1. Người dùng (mật khẩu chỉ để demo; ứng dụng thật phải băm bằng BCrypt/PBKDF2)
INSERT INTO Users (FullName, Email, PasswordHash, PhoneNumber, Role) VALUES
(N'Nguyễn Quản Trị', N'admin@hotelbooking.vn', N'DEMO_HASH_ADMIN', N'0901000001', N'Admin'),
(N'Trần Minh Anh',   N'minhanh@gmail.com',     N'DEMO_HASH_USER2', N'0901000002', N'Member'),
(N'Lê Hoàng Nam',    N'hoangnam@gmail.com',    N'DEMO_HASH_USER3', N'0901000003', N'Member'),
(N'Phạm Thu Hà',     N'thuha@gmail.com',       N'DEMO_HASH_USER4', N'0901000004', N'Member'),
(N'Võ Quốc Bảo',     N'quocbao@gmail.com',     N'DEMO_HASH_USER5', N'0901000005', N'Member'),
(N'Đặng Gia Hân',    N'giahan@gmail.com',      N'DEMO_HASH_USER6', N'0901000006', N'Member');

-- 5.2. 20 khách sạn ở 20 điểm đến (HotelId 1..20)
INSERT INTO Hotels (HotelName, City, Region, Address, StarRating, Description, ThumbnailUrl) VALUES
(N'Capella Hanoi Opera & Heritage Suites',   N'Hà Nội',          N'Miền Bắc',   N'Khu phố cổ Hoàn Kiếm, Hà Nội',    5, N'Khách sạn di sản cạnh Nhà hát Lớn.',             N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80'),
(N'Làng Nổi Vịnh Lam Ngọc Yacht & Resort',   N'Hạ Long',         N'Miền Bắc',   N'Bãi Cháy, Hạ Long',               5, N'Nghỉ dưỡng giữa vịnh đảo đá vôi.',               N'https://images.unsplash.com/photo-1540202404-a2f29016b523?auto=format&fit=crop&w=800&q=80'),
(N'Thung Lũng Mây Mường Hoa Ecolodge',       N'Sa Pa',           N'Miền Bắc',   N'Thung lũng Mường Hoa, Sa Pa',     4, N'Ecolodge nhìn ruộng bậc thang.',                 N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=800&q=80'),
(N'Bản Đá Cổ Đồng Văn Karst Retreat',        N'Hà Giang',        N'Miền Bắc',   N'Phố cổ Đồng Văn, Hà Giang',       4, N'Nhà trình tường giữa cao nguyên đá.',            N'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=800&q=80'),
(N'Đồi Chè Sương Sớm Glamping & Hobbit',     N'Mộc Châu',        N'Miền Bắc',   N'Thung lũng Nà Ka, Mộc Châu',      4, N'Glamping và nhà Hobbit giữa đồi chè.',           N'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=800&q=80'),
(N'Cố Đô Tràng An Lotus Lagoon Resort',      N'Ninh Bình',       N'Miền Bắc',   N'Khu du lịch Tràng An, Ninh Bình', 5, N'Resort ven đầm sen dưới chân Hang Múa.',         N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80'),
(N'Vịnh Lan Hạ Cliffside Bungalow',          N'Cát Bà',          N'Miền Bắc',   N'Thị trấn Cát Bà, Hải Phòng',      4, N'Bungalow trên ghềnh đá nhìn vịnh Lan Hạ.',       N'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80'),
(N'Suối Moọc Phong Nha Jungle Lodge',        N'Quảng Bình',      N'Miền Trung', N'Phong Nha - Kẻ Bàng',             4, N'Nhà gỗ giữa rừng nguyên sinh.',                  N'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=800&q=80'),
(N'Vườn Tịnh Tâm Cố Đô Heritage Onsen',      N'Huế',             N'Miền Trung', N'Ven sông Hương, Huế',             5, N'Nhà vườn Huế kết hợp tắm khoáng Onsen.',         N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=800&q=80'),
(N'Bán Đảo Sơn Trà Ocean Pool Villas',       N'Đà Nẵng',         N'Miền Trung', N'Bán đảo Sơn Trà, Đà Nẵng',        5, N'Villa hồ bơi riêng giữa rừng và biển.',          N'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=800&q=80'),
(N'Bến Đèn Lồng Hoài Giang Boutique',        N'Hội An',          N'Miền Trung', N'Bờ sông Hoài, Hội An',            4, N'Boutique hotel cạnh phố cổ đèn lồng.',           N'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=800&q=80'),
(N'Eo Gió Kỳ Co Cliff Ocean Resort',         N'Quy Nhơn',        N'Miền Trung', N'Nhơn Lý, Quy Nhơn',               5, N'Resort trên vách đá nhìn biển Kỳ Co.',           N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80'),
(N'Ghềnh Đá Đĩa Hoa Vàng Cỏ Xanh Villa',     N'Phú Yên',         N'Miền Trung', N'Vịnh Xuân Đài, Phú Yên',          4, N'Villa hoang sơ gần Gành Đá Đĩa.',                N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=800&q=80'),
(N'Đảo Yến Vịnh Ninh Vân Overwater Villa',   N'Nha Trang',       N'Miền Trung', N'Vịnh Ninh Vân, Nha Trang',        5, N'Villa gỗ trên mặt nước.',                        N'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=800&q=80'),
(N'Chạm Mây Boutique Resort & Spa Đà Lạt',   N'Đà Lạt',          N'Miền Trung', N'Đồi Dã Chiến, Phường 11, Đà Lạt', 5, N'Quần thể nghỉ dưỡng 4 phân khu giữa đồi thông.', N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=800&q=80'),
(N'Đồi Cát Bay Bàu Trắng Oasis Resort',      N'Mũi Né',          N'Miền Nam',   N'Hàm Tiến, Mũi Né',                4, N'Ốc đảo nghỉ dưỡng cạnh đồi cát hồng.',           N'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=800&q=80'),
(N'Hồ Tràm Rừng Nguyên Sinh Seaview Villa',  N'Vũng Tàu',        N'Miền Nam',   N'Hồ Tràm, Vũng Tàu',               5, N'Villa ven rừng Phước Bửu nhìn biển.',            N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=800&q=80'),
(N'K''s Luxury Sky Residence Thảo Điền',     N'TP. Hồ Chí Minh', N'Miền Nam',   N'Thảo Điền, TP. Hồ Chí Minh',      5, N'Căn hộ cao cấp ven sông Sài Gòn.',               N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=800&q=80'),
(N'Cồn Sơn Miệt Vườn Mekong Eco-Retreat',    N'Cần Thơ',         N'Miền Nam',   N'Cồn Sơn, Bình Thủy, Cần Thơ',     4, N'Homestay miệt vườn trên cù lao sông Hậu.',       N'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=800&q=80'),
(N'Mũi Ông Đội Coral Reef Peninsula Villas', N'Phú Quốc',        N'Miền Nam',   N'Mũi Ông Đội, Phú Quốc',           5, N'Villa trên ghềnh đá hai mặt biển.',              N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80');

-- 5.3. Loại phòng
--      RoomTypeId 1..6  : 6 hạng phòng của Chạm Mây Đà Lạt (HotelId 15), chia 4 phân khu
--      RoomTypeId 7..25 : mỗi khách sạn còn lại 1 hạng phòng (theo thứ tự HotelId, bỏ qua 15)
INSERT INTO RoomTypes (HotelId, ZoneName, TypeName, Description, PricePerNight, OldPrice, MaxGuests, Area, BedType, ThumbnailUrl) VALUES
(15, N'Đồi Thông Tinh Mơ',       N'Pine Whisper Studio',        N'Ban công rừng thông sương sớm',            1680000, 2200000, 2,  36, N'1 giường King',         N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=800&q=80'),
(15, N'Đồi Thông Tinh Mơ',       N'Grand Pine Panorama Deluxe', N'Bồn tắm đá ngâm thảo mộc nhìn rừng thông', 1950000, 2650000, 3,  45, N'1 giường Super King',   N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=800&q=80'),
(15, N'Thung Lũng Săn Mây',      N'Cloud Horizon Suite',        N'Sân hiên săn mây 180 độ & lò sưởi',        2680000, 3300000, 3,  58, N'1 giường Super King',   N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=800&q=80'),
(15, N'Thung Lũng Săn Mây',      N'Duplex Sky Loft',            N'Gác mái thông tầng ngắm sao',              3150000, 3850000, 4,  68, N'2 giường Queen',        N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=800&q=80'),
(15, N'Biệt Thự Vườn Hồng Cổ',   N'Rose Garden Pool Villa 2PN', N'Hồ bơi nước ấm riêng, bếp đảo, vườn BBQ',  4450000, 5400000, 6, 145, N'2 phòng ngủ King',      N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=800&q=80'),
(15, N'Làng Glamping Suối Mơ',   N'Luxury Forest Dome Tent',    N'Lều vòm sưởi sàn, bồn gỗ Pơ-mu ven suối',  1490000, 1950000, 2,  40, N'1 giường King',         N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=800&q=80'),
(1,  N'Khu Phố Cổ Di Sản',            N'Heritage Opera Suite',       N'Suite nhìn Nhà hát Lớn',          2450000, 3100000, 2,  48, N'1 giường King',         N'https://images.unsplash.com/photo-1566073771259-6a8506099945?auto=format&fit=crop&w=800&q=80'),
(2,  N'Vịnh Đảo Đá Vôi Biệt Lập',     N'Floating Bay Villa',         N'Villa nổi nhìn vịnh',             2280000, 2950000, 3,  55, N'1 giường King',         N'https://images.unsplash.com/photo-1540202404-a2f29016b523?auto=format&fit=crop&w=800&q=80'),
(3,  N'Ruộng Bậc Thang Săn Mây',      N'Terrace Cloud Cabin',        N'Cabin gỗ nhìn ruộng bậc thang',   1650000, 2200000, 2,  32, N'1 giường Queen',        N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=800&q=80'),
(4,  N'Cao Nguyên Đá Mã Pí Lèng',     N'Rammed Earth House',         N'Nhà trình tường truyền thống',    1480000, 1950000, 3,  40, N'2 giường đôi',          N'https://images.unsplash.com/photo-1506744038136-46273834b3fb?auto=format&fit=crop&w=800&q=80'),
(5,  N'Thung Lũng Mận Nà Ka',         N'Tea Hill Hobbit House',      N'Nhà Hobbit giữa đồi chè',         1390000, 1850000, 2,  28, N'1 giường Queen',        N'https://images.unsplash.com/photo-1501785888041-af3ef285b470?auto=format&fit=crop&w=800&q=80'),
(6,  N'Đầm Sen Hang Múa',             N'Lotus Lagoon Bungalow',      N'Bungalow ven đầm sen',            1750000, 2300000, 2,  38, N'1 giường King',         N'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=800&q=80'),
(7,  N'Ghềnh Đá Vịnh Lan Hạ',         N'Cliffside Bay Bungalow',     N'Bungalow vách đá nhìn vịnh',      1920000, 2490000, 2,  35, N'1 giường King',         N'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?auto=format&fit=crop&w=800&q=80'),
(8,  N'Rừng Nguyên Sinh Kẻ Bàng',     N'Jungle Stream Lodge',        N'Nhà gỗ ven suối Moọc',            1520000, 1980000, 3,  42, N'1 giường King + 1 đơn', N'https://images.unsplash.com/photo-1448375240586-882707db888b?auto=format&fit=crop&w=800&q=80'),
(9,  N'Đồi Vọng Cảnh Sông Hương',     N'Royal Garden House & Onsen', N'Nhà rường có bồn khoáng riêng',   1820000, 2400000, 2,  50, N'1 giường King',         N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=800&q=80'),
(10, N'Rừng Biển Sơn Trà',            N'Ocean Pool Villa',           N'Villa hồ bơi riêng nhìn biển',    2150000, 2800000, 4,  90, N'2 giường King',         N'https://images.unsplash.com/photo-1571896349842-33c89424de2d?auto=format&fit=crop&w=800&q=80'),
(11, N'Làng Lụa & Rừng Dừa Bảy Mẫu',  N'Lantern River Deluxe',       N'Phòng ban công nhìn sông Hoài',   1890000, 2550000, 2,  34, N'1 giường King',         N'https://images.unsplash.com/photo-1559592413-7cec4d0cae2b?auto=format&fit=crop&w=800&q=80'),
(12, N'Làng Chài Nhơn Lý',            N'Cliff Ocean Room',           N'Phòng vách đá nhìn biển Kỳ Co',   1780000, 2350000, 2,  36, N'1 giường King',         N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80'),
(13, N'Vịnh Xuân Đài Hoang Sơ',       N'Golden Flower Garden Villa', N'Villa vườn cỏ xanh',              1620000, 2100000, 4,  80, N'2 giường Queen',        N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=800&q=80'),
(14, N'Nhà Gỗ Trên Biển Ninh Vân',    N'Overwater Wooden Villa',     N'Villa gỗ trên mặt nước',          2490000, 3200000, 2,  60, N'1 giường King',         N'https://images.unsplash.com/photo-1573843981267-be1999ff37cd?auto=format&fit=crop&w=800&q=80'),
(16, N'Ốc Đảo Biển Đồi Cát Hồng',     N'Dune Oasis Bungalow',        N'Bungalow nhìn đồi cát',           1580000, 2150000, 2,  36, N'1 giường King',         N'https://images.unsplash.com/photo-1564501049412-61c2a3083791?auto=format&fit=crop&w=800&q=80'),
(17, N'Rừng Phước Bửu & Biển Hồ Tràm',N'Forest Seaview Villa',       N'Villa ven rừng nhìn biển',        1690000, 2250000, 4,  85, N'2 giường King',         N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=800&q=80'),
(18, N'Biệt Thự Ven Sông Sài Gòn',    N'Sky Riverside Apartment',    N'Căn hộ tầng cao nhìn sông',       1950000, 2500000, 3,  65, N'1 giường King + Sofa',  N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=800&q=80'),
(19, N'Cù Lao Sông Hậu & Chợ Nổi',    N'Mekong Orchard House',       N'Nhà vườn giữa vườn trái cây',     1290000, 1750000, 3,  45, N'2 giường đôi',          N'https://images.unsplash.com/photo-1611892440504-42a792e24d32?auto=format&fit=crop&w=800&q=80'),
(20, N'Ghềnh Đá 2 Mặt Biển',          N'Coral Reef Pool Villa',      N'Villa hồ bơi hai mặt biển',       2750000, 3600000, 4, 120, N'2 giường King',         N'https://images.unsplash.com/photo-1540541338287-41700207dee6?auto=format&fit=crop&w=800&q=80');

-- 5.4. Ảnh phòng
-- 6 hạng phòng Đà Lạt: mỗi hạng 8 ảnh (bộ sưu tập trên trang Chi tiết)
INSERT INTO RoomTypeImages (RoomTypeId, ImageUrl, Caption, SortOrder)
SELECT rt.RoomTypeId, img.ImageUrl, img.Caption, img.SortOrder
FROM RoomTypes rt
CROSS JOIN (VALUES
    (1, N'https://images.unsplash.com/photo-1590490360182-c33d57733427?auto=format&fit=crop&w=1000&q=80', N'Phòng ngủ chính'),
    (2, N'https://images.unsplash.com/photo-1582719508461-905c673771fd?auto=format&fit=crop&w=1000&q=80', N'Ban công nhìn rừng thông'),
    (3, N'https://images.unsplash.com/photo-1584622650111-993a426fbf0a?auto=format&fit=crop&w=1000&q=80', N'Phòng tắm bồn đá'),
    (4, N'https://images.unsplash.com/photo-1578683010236-d716f9a3f461?auto=format&fit=crop&w=1000&q=80', N'Góc sofa & lò sưởi'),
    (5, N'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?auto=format&fit=crop&w=1000&q=80', N'Hồ bơi nước ấm'),
    (6, N'https://images.unsplash.com/photo-1540555700478-4be289fbecef?auto=format&fit=crop&w=1000&q=80', N'Khu Onsen & xông hơi'),
    (7, N'https://images.unsplash.com/photo-1556911220-bff31c812dba?auto=format&fit=crop&w=1000&q=80',   N'Bếp & bàn ăn'),
    (8, N'https://images.unsplash.com/photo-1528127269322-539801943592?auto=format&fit=crop&w=1000&q=80', N'Sân hiên săn mây')
) img(SortOrder, ImageUrl, Caption)
WHERE rt.HotelId = 15;

-- Các hạng phòng còn lại: lấy ảnh đại diện làm ảnh số 1
INSERT INTO RoomTypeImages (RoomTypeId, ImageUrl, Caption, SortOrder)
SELECT RoomTypeId, ThumbnailUrl, N'Ảnh đại diện', 1
FROM RoomTypes
WHERE HotelId <> 15 AND ThumbnailUrl IS NOT NULL;

-- 5.5. Phòng vật lý
-- Chạm Mây Đà Lạt: mã phòng có tiền tố theo phân khu (G02 đang bảo trì)
INSERT INTO Rooms (RoomTypeId, RoomNumber, Floor, IsActive) VALUES
(1, N'P101', 1, 1),
(1, N'P102', 1, 1),
(2, N'P201', 2, 1),
(2, N'P202', 2, 1),
(3, N'C101', 1, 1),
(3, N'C102', 1, 1),
(4, N'C201', 2, 1),
(5, N'V01',  1, 1),
(5, N'V02',  1, 1),
(6, N'G01',  1, 1),
(6, N'G02',  1, 0);

-- Các khách sạn còn lại: mỗi hạng phòng 2 phòng 101, 102
INSERT INTO Rooms (RoomTypeId, RoomNumber, Floor, IsActive)
SELECT rt.RoomTypeId, n.RoomNumber, 1, 1
FROM RoomTypes rt
CROSS JOIN (VALUES (N'101'), (N'102')) n(RoomNumber)
WHERE rt.HotelId <> 15
ORDER BY rt.RoomTypeId, n.RoomNumber;

-- 5.6. Tiện nghi
INSERT INTO Amenities (AmenityName, Category) VALUES
(N'Wi-Fi miễn phí trong phòng',      N'Internet'),
(N'Internet cáp quang tốc độ cao',   N'Internet'),
(N'Hồ bơi nước ấm',                  N'Thư giãn'),
(N'Spa & phòng xông hơi',            N'Thư giãn'),
(N'Suối khoáng nóng Onsen',          N'Thư giãn'),
(N'Vườn & đường dạo bộ',             N'Thư giãn'),
(N'Bộ dụng cụ sơ cứu',               N'An toàn'),
(N'Khử trùng chuyên nghiệp',         N'An toàn'),
(N'Bảo vệ 24 giờ',                   N'An toàn'),
(N'Đưa đón sân bay',                 N'Dịch vụ'),
(N'Dọn phòng hằng ngày',             N'Dịch vụ'),
(N'Giữ hành lý',                     N'Dịch vụ'),
(N'Lễ tân 24 giờ',                   N'Dịch vụ'),
(N'Bữa sáng miễn phí',               N'Dịch vụ'),
(N'Ấm nước điện',                    N'Trong phòng'),
(N'Điều hòa 2 chiều',                N'Trong phòng'),
(N'Máy sấy tóc',                     N'Trong phòng'),
(N'Két sắt',                         N'Trong phòng'),
(N'Bồn tắm đá',                      N'Trong phòng'),
(N'Lò sưởi',                         N'Trong phòng'),
(N'Bếp đầy đủ',                      N'Trong phòng'),
(N'Máy pha cà phê',                  N'Trong phòng');

-- Tiện nghi cơ bản: gán cho mọi loại phòng
INSERT INTO RoomTypeAmenities (RoomTypeId, AmenityId)
SELECT rt.RoomTypeId, a.AmenityId
FROM RoomTypes rt
CROSS JOIN Amenities a
WHERE a.AmenityName IN (N'Wi-Fi miễn phí trong phòng', N'Ấm nước điện', N'Điều hòa 2 chiều',
                        N'Máy sấy tóc', N'Két sắt', N'Dọn phòng hằng ngày', N'Lễ tân 24 giờ',
                        N'Bộ dụng cụ sơ cứu', N'Bảo vệ 24 giờ');

-- Tiện nghi riêng của 6 hạng phòng Đà Lạt
INSERT INTO RoomTypeAmenities (RoomTypeId, AmenityId)
SELECT v.RoomTypeId, a.AmenityId
FROM (VALUES
    (1, N'Bữa sáng miễn phí'),
    (1, N'Vườn & đường dạo bộ'),
    (2, N'Bồn tắm đá'),
    (2, N'Máy pha cà phê'),
    (2, N'Suối khoáng nóng Onsen'),
    (3, N'Lò sưởi'),
    (3, N'Máy pha cà phê'),
    (4, N'Lò sưởi'),
    (4, N'Máy pha cà phê'),
    (5, N'Hồ bơi nước ấm'),
    (5, N'Bếp đầy đủ'),
    (5, N'Đưa đón sân bay'),
    (6, N'Suối khoáng nóng Onsen'),
    (6, N'Spa & phòng xông hơi')
) v(RoomTypeId, AmenityName)
INNER JOIN Amenities a ON a.AmenityName = v.AmenityName;

-- 5.7. Mã giảm giá (CouponId 1..3, khớp 3 thẻ trên trang chủ)
INSERT INTO Coupons (Code, Title, DiscountType, DiscountValue, MaxDiscount, MinOrderAmount,
                     MinLoyaltyPoints, IsNewUserOnly, StartDate, EndDate) VALUES
(N'CHAMBANMOI', N'Giảm tới 250.000đ cho lần đặt phòng đầu tiên', N'Fixed',   250000, NULL,   1200000,   0, 1, '2026-01-01', '2026-12-31'),
(N'CHAMLUX15',  N'Giảm 15% (tối đa 500K) Biệt thự & Glamping',  N'Percent', 15,     500000, 0,       100, 0, '2026-01-01', '2026-12-31'),
(N'CHAMSANBAY', N'Giảm 100.000đ khi đặt kèm xe đưa đón sân bay', N'Fixed',   100000, NULL,   1000000,   0, 0, '2026-01-01', '2026-12-31');

-- 5.8. Đơn đặt phòng
-- Tạo đơn ở trạng thái Pending/Confirmed trước, chèn chi tiết để trigger tính tiền,
-- sau đó mới cập nhật Completed/Cancelled để trigger cộng điểm đúng.
-- DiscountAmount là số tiền Controller đã tính từ mã giảm giá lúc khách đặt.
INSERT INTO Bookings (UserId, CouponId, DiscountAmount, CheckInDate, CheckOutDate, Status, CreatedAt) VALUES
(2, NULL,      0, '2026-10-10', '2026-10-13', N'Confirmed', '2026-10-01'),  -- 1: Đà Lạt
(2, 2,    500000, '2026-11-01', '2026-11-03', N'Confirmed', '2026-10-20'),  -- 2: Đà Lạt, CHAMLUX15 (15% chạm trần 500K)
(3, 1,    250000, '2026-11-05', '2026-11-07', N'Confirmed', '2026-11-01'),  -- 3: Phú Quốc, CHAMBANMOI
(4, NULL,      0, '2026-11-15', '2026-11-17', N'Pending',   '2026-11-07'),  -- 4: Đà Lạt villa
(5, NULL,      0, '2026-10-20', '2026-10-22', N'Pending',   '2026-10-15'),  -- 5: sẽ bị hủy
(6, NULL,      0, '2026-09-12', '2026-09-14', N'Confirmed', '2026-09-05'),  -- 6: Hà Nội
(3, NULL,      0, '2026-10-25', '2026-10-28', N'Confirmed', '2026-10-18'),  -- 7: Đà Lạt, 2 phòng
(4, NULL,      0, '2026-12-01', '2026-12-05', N'Confirmed', '2026-11-06');  -- 8: Đà Nẵng

-- Chèn chi tiết theo (Khách sạn, Số phòng); UnitPrice lấy từ giá hiện tại của loại phòng
INSERT INTO BookingDetails (BookingId, RoomId, UnitPrice)
SELECT v.BookingId, r.RoomId, rt.PricePerNight
FROM (VALUES
    (1, 15, N'P101'),
    (2, 15, N'C101'),
    (3, 20, N'101'),
    (4, 15, N'V01'),
    (5, 15, N'P201'),
    (6, 1,  N'101'),
    (7, 15, N'G01'),
    (7, 15, N'P102'),
    (8, 10, N'101')
) v(BookingId, HotelId, RoomNumber)
INNER JOIN Rooms r      ON r.RoomNumber = v.RoomNumber
INNER JOIN RoomTypes rt ON rt.RoomTypeId = r.RoomTypeId AND rt.HotelId = v.HotelId;

-- Kết quả trigger tính tiền (SubTotal - DiscountAmount = TotalAmount):
--   Đơn 1: 1.680.000 x 3 đêm                       =  5.040.000
--   Đơn 2: 2.680.000 x 2 = 5.360.000 - 500.000     =  4.860.000
--   Đơn 3: 2.750.000 x 2 = 5.500.000 - 250.000     =  5.250.000
--   Đơn 4: 4.450.000 x 2                           =  8.900.000
--   Đơn 5: 1.950.000 x 2                           =  3.900.000
--   Đơn 6: 2.450.000 x 2                           =  4.900.000
--   Đơn 7: (1.490.000 + 1.680.000) x 3             =  9.510.000
--   Đơn 8: 2.150.000 x 4                           =  8.600.000

-- Cập nhật trạng thái -> trigger cộng điểm (chỉ đơn Completed)
UPDATE Bookings SET Status = N'Completed' WHERE BookingId IN (1, 2, 6, 7);
UPDATE Bookings SET Status = N'Cancelled' WHERE BookingId = 5;
-- Điểm: UserId 2 = 50 + 48 = 98; UserId 3 = 95; UserId 6 = 49; còn lại = 0

-- 5.9. Thanh toán
INSERT INTO Payments (BookingId, PaymentMethod, Amount, PaymentDate, Status, TransactionCode) VALUES
(1, N'Card',   5040000, '2026-10-10', N'Completed', N'CARD-20261010-0001'),
(2, N'MoMo',   4860000, '2026-11-01', N'Completed', N'MOMO-20261101-0002'),
(3, N'VietQR', 2625000, '2026-11-01', N'Completed', N'VQR-20261101-0003'),   -- cọc 50%
(3, N'Cash',   2625000, '2026-11-05', N'Pending',   NULL),                   -- trả tại quầy
(4, N'Cash',   8900000, '2026-11-15', N'Pending',   NULL),
(5, N'MoMo',   3900000, '2026-10-20', N'Failed',    N'MOMO-20261020-0005'),
(6, N'Cash',   4900000, '2026-09-12', N'Completed', NULL),
(7, N'VietQR', 9510000, '2026-10-25', N'Completed', N'VQR-20261025-0007'),
(8, N'Card',   8600000, '2026-11-06', N'Completed', N'CARD-20261106-0008');

-- 5.10. Đánh giá (gắn BookingId của đơn Completed = đã xác thực)
INSERT INTO Reviews (UserId, RoomTypeId, BookingId, Rating, CleanlinessScore, LocationScore,
                     ServiceScore, FacilitiesScore, ValueForMoneyScore, Title, Comment, CreatedAt) VALUES
(2, 1, 1, 9.6, 10, 10,  9, 9, 9, N'Ban công nhìn thẳng ra rừng thông',
    N'Phòng sạch, buổi sáng mở cửa là thấy sương. Bữa sáng ngon.', '2026-10-14'),
(2, 3, 2, 9.8, 10, 10, 10, 9, 9, N'Sáng mở rèm ra là biển mây tràn vào hiên gỗ',
    N'Suite có lò sưởi rất ấm, xe đưa đón sân bay Liên Khương đúng giờ.', '2026-11-04'),
(3, 6, 7, 9.4,  9, 10,  9, 9, 9, N'Glamping có sưởi sàn và Onsen rất chill',
    N'Ban đêm nghe tiếng suối, buổi tối có lửa trại.', '2026-10-29'),
(3, 1, 7, 9.0,  9,  9,  9, 9, 8, N'Phòng yên tĩnh, cách âm tốt',
    N'Giường êm, nhân viên hỗ trợ nhận phòng nhanh.', '2026-10-29'),
(6, 7, 6, 9.5, 10, 10,  9, 9, 9, N'Vị trí đẹp ngay cạnh Nhà hát Lớn',
    N'Đi bộ ra Hồ Gươm vài phút, phòng mang phong cách Pháp cổ.', '2026-09-15');
GO

-- =====================================================================
-- 6. KIỂM TRA NHANH
-- =====================================================================

-- Điểm tích lũy (mong đợi: UserId 2 = 98, 3 = 95, 6 = 49, còn lại 0)
SELECT UserId, FullName, Role, LoyaltyPoints FROM Users;

-- Tiền từng đơn do trigger tính
SELECT BookingId, UserId, CouponId, Status, SubTotal, DiscountAmount, TotalAmount
FROM Bookings
ORDER BY BookingId;

-- Điểm trung bình & giá thấp nhất theo khách sạn (dùng cho Card trang chủ)
SELECT * FROM vw_HotelRatingSummary ORDER BY Region, City;

-- Đếm số bảng (mong đợi 12)
SELECT COUNT(*) AS SoBang FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE';
