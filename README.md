# Olist E-Commerce Supply Chain Analysis 🇧🇷

## 📊 Project Overview
This project analyzes 100k+ orders from the Olist E-Commerce dataset to identify bottlenecks in logistics and their impact on revenue.
**Goal:** Transform raw data into a "360-degree" view of Sales and Operations.

![Dashboard Overview](dashboard_overview.png)

## 🔍 Key Insights
* **Logistics:** Engineered a "Delivery Status" metric to track On-Time vs. Late performance.
* **Seasonality:** Used Time Intelligence (DAX) to track Month-over-Month (MoM) growth.
* **Geography:** Mapped delivery performance across Brazilian states.

## 🛠 Tools Used
* **Power BI:** Data Modeling (Star Schema), DAX Measures (CALCULATE, Time Intelligence).
* **SQL:** Logic design for data categorization and shipping performance.

## 💻 Logic Design (SQL)
Although the final visualization uses Power BI, the logic was designed using SQL Common Table Expressions (CTEs) to categorize delivery speeds:

```sql
/* Logic for Delivery Status */
SELECT 
    order_id,
    delivery_date,
    estimated_date,
    CASE 
        WHEN delivery_date > estimated_date THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status
FROM orders;
```
##🧠 Technical Highlights
Star Schema Modeling: Connected Fact tables (Orders) to Dimensions (Customers, Products).

Advanced DAX: MoM Growth % using VAR and CALCULATE for time-series analysis.
