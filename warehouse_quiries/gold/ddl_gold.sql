/*
===============================================================================
DDL Script: Create Gold Views (Wrapped in Stored Procedure)
===============================================================================

Script Purpose:
    This stored procedure creates views for the Gold layer in the data warehouse. 
    The Gold layer contains analytical views that follow a star schema format:
        - Dimension Views
        - Fact Views

    These views apply transformations and joins on top of the Silver layer 
    to build clean, denormalized, business-ready datasets for reporting and BI.

Views Created:
    1. gold.dim_customers     - Customer dimension with CRM + ERP details
    2. gold.dim_products      - Product dimension with active products
    3. gold.fact_sales        - Sales fact table with links to products/customers

Usage:
    EXEC sp_create_gold_views;

Note:
    These views are used directly by analysts or BI tools for reporting.
    No data is stored in the gold layer; only logic via views.
===============================================================================
*/

USE data_warehouse_prj;
GO

CREATE OR ALTER PROCEDURE sp_create_gold_views AS
BEGIN
    SET NOCOUNT ON;

    -- ============================================================================
    -- 1. Create Dimension View: gold.dim_customers
    -- ============================================================================
    IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
        DROP VIEW gold.dim_customers;

    EXEC('
    CREATE VIEW gold.dim_customers AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY cst_id) AS customer_key,
        ci.cst_id                            AS customer_id,
        ci.cst_key                           AS customer_number,
        ci.cst_firstname                     AS first_name,
        ci.cst_lastname                      AS last_name,
        la.cntry                             AS country,
        ci.cst_marital_status                AS marital_status,
        CASE 
            WHEN ci.cst_gndr != ''n/a'' THEN ci.cst_gndr
            ELSE COALESCE(ca.gen, ''n/a'')
        END                                AS gender,
        ca.bdate                             AS birthdate,
        ci.cst_create_date                   AS create_date
    FROM silver.crm_cust_info ci
    LEFT JOIN silver.erp_cust_az12 ca
        ON ci.cst_key = ca.cid
    LEFT JOIN silver.erp_loc_a101 la
        ON ci.cst_key = la.cid
    ');

    -- ============================================================================
    -- 2. Create Dimension View: gold.dim_products
    -- ============================================================================
    IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
        DROP VIEW gold.dim_products;

    EXEC('
    CREATE VIEW gold.dim_products AS
    SELECT
        ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
        pn.prd_id       AS product_id,
        pn.prd_key      AS product_number,
        pn.prd_nm       AS product_name,
        pn.cat_id       AS category_id,
        pc.cat          AS category,
        pc.subcat       AS subcategory,
        pc.maintenance  AS maintenance,
        pn.prd_cost     AS cost,
        pn.prd_line     AS product_line,
        pn.prd_start_dt AS start_date
    FROM silver.crm_prd_info pn
    LEFT JOIN silver.erp_px_cat_g1v2 pc
        ON pn.cat_id = pc.id
    WHERE pn.prd_end_dt IS NULL
    ');

    -- ============================================================================
    -- 3. Create Fact View: gold.fact_sales
    -- ============================================================================
    IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
        DROP VIEW gold.fact_sales;

    EXEC('
    CREATE VIEW gold.fact_sales AS
    SELECT
        sd.sls_ord_num      AS order_number,
        pr.product_key      AS product_key,
        cu.customer_key     AS customer_key,
        sd.sls_order_dt     AS order_date,
        sd.sls_ship_dt      AS shipping_date,
        sd.sls_due_dt       AS due_date,
        sd.sls_sales        AS sales_amount,
        sd.sls_quantity     AS quantity,
        sd.sls_price        AS price
    FROM silver.crm_sales_details sd
    LEFT JOIN gold.dim_products pr
        ON sd.sls_prd_key = pr.product_number
    LEFT JOIN gold.dim_customers cu
        ON sd.sls_cust_id = cu.customer_id
    ');
END;
GO