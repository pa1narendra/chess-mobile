import mongoose from 'mongoose';
import { Game } from '../schemas/game';
import { User } from '../schemas/user';

// Model Map for the chess application
const modelMap: { [key: string]: mongoose.Model<any> } = {
    Games: Game,
    Users: User
};

// Custom Error Classes
class NotFoundError extends Error {
    status: number;
    constructor(message: string) {
        super(message);
        this.name = "NotFoundError";
        this.status = 404;
    }
}

class ValidationError extends Error {
    status: number;
    details: any;
    constructor(message: string, details?: any) {
        super(message);
        this.name = "ValidationError";
        this.status = 400;
        this.details = details;
    }
}

// Helper to get a model
export function getModel(tableName: string) {
    const model = modelMap[tableName];
    if (!model) throw new NotFoundError(`No model found for table: ${tableName}`);
    return model;
}

// Helper function to convert strings to ObjectIds and Dates based on schema
function convertStringsToObjectIdsAndDates(obj: any, schema: mongoose.Schema<any>) {
    if (!obj || typeof obj !== "object") return obj;

    for (const key of Object.keys(obj)) {
        const schemaType = schema.path(key);

        // Handle direct ObjectId fields
        if (
            schemaType &&
            (schemaType.instance === "ObjectID" || schemaType.instance === "ObjectId")
        ) {
            if (typeof obj[key] === "string" && mongoose.Types.ObjectId.isValid(obj[key])) {
                obj[key] = new mongoose.Types.ObjectId(obj[key]);
            }
            if (Array.isArray(obj[key])) {
                obj[key] = obj[key].map((v: any) =>
                    typeof v === "string" && mongoose.Types.ObjectId.isValid(v)
                        ? new mongoose.Types.ObjectId(v)
                        : v
                );
            }
        }
        // Handle arrays of ObjectIds
        else if (
            schemaType &&
            schemaType.instance === "Array" &&
            // @ts-ignore
            schemaType.caster &&
            // @ts-ignore
            (schemaType.caster.instance === "ObjectID" || schemaType.caster.instance === "ObjectId")
        ) {
            if (obj[key] && typeof obj[key] === "object") {
                for (const op of ["$in", "$all", "$nin", "$or", "$and"]) {
                    if (obj[key][op] && Array.isArray(obj[key][op])) {
                        obj[key][op] = obj[key][op].map((v: any) =>
                            typeof v === "string" && mongoose.Types.ObjectId.isValid(v)
                                ? new mongoose.Types.ObjectId(v)
                                : v
                        );
                    }
                }
            }
        }
        // Handle Date fields
        else if (schemaType && schemaType.instance === "Date") {
            // If the value is a string, convert to Date
            if (typeof obj[key] === "string") {
                obj[key] = new Date(obj[key]);
            }
            // If the value is an object with $gte/$lte/$gt/$lt, convert those
            if (typeof obj[key] === "object" && obj[key] !== null) {
                for (const op of ["$gte", "$lte", "$gt", "$lt", "$eq", "$ne"]) {
                    if (obj[key][op] && typeof obj[key][op] === "string") {
                        obj[key][op] = new Date(obj[key][op]);
                    }
                }
            }
        }
        // Recursively handle nested objects
        else if (typeof obj[key] === "object" && obj[key] !== null) {
            obj[key] = convertStringsToObjectIdsAndDates(obj[key], schema);
        }
    }
    return obj;
}

const searchService = {
    // Create a new resource
    createResource: async (tableName: string, body: any) => {
        try {
            const Model = getModel(tableName);

            // Convert string ObjectIds to MongoDB ObjectIds before creating the document
            const convertedBody = convertStringsToObjectIdsAndDates(body, Model.schema);

            const doc = new Model(convertedBody);
            const result = await doc.save();
            return { success: true, data: result };
        } catch (error: any) {
            if (error.name === "ValidationError") {
                return {
                    success: false,
                    error: "Validation failed",
                    details: error.errors || error.message
                };
            }
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to create resource" };
        }
    },

    // Advanced search with aggregation pipeline and pagination
    searchResource: async (
        tableName: string,
        queryBody: any = {},
        options?: { page?: number; pageSize?: number }
    ) => {
        try {
            const Model = getModel(tableName);

            // Extract options from queryBody or options param
            const {
                filter = {},
                sort = { _id: -1 },
                project,
                lookups,
                unwind,
                addFields,
                customStages,
                ...rest
            } = queryBody;

            // Convert string ObjectIds in filter to real ObjectIds
            const convertedFilter = convertStringsToObjectIdsAndDates({ ...filter }, Model.schema);

            // Pagination
            const page = options?.page || rest.page || 1;
            const pageSize = options?.pageSize || rest.pageSize || 20;
            const skip = (page - 1) * pageSize;

            // Build the aggregation pipeline dynamically
            const pipeline: any[] = [];

            // $match
            if (convertedFilter && Object.keys(convertedFilter).length > 0) {
                pipeline.push({ $match: convertedFilter });
            }

            // $addFields
            if (addFields) {
                pipeline.push({ $addFields: addFields });
            }

            // $lookup (array of lookups)
            if (Array.isArray(lookups)) {
                for (const lookup of lookups) {
                    pipeline.push({ $lookup: lookup });
                }
            }

            // $unwind
            if (unwind) {
                if (Array.isArray(unwind)) {
                    unwind.forEach(u => pipeline.push({ $unwind: u }));
                } else {
                    pipeline.push({ $unwind: unwind });
                }
            }

            // $sort
            if (sort) {
                pipeline.push({ $sort: sort });
            }

            // $project
            if (project) {
                pipeline.push({ $project: project });
            }

            // Custom stages (for advanced users)
            if (Array.isArray(customStages)) {
                pipeline.push(...customStages);
            }

            // $facet for pagination and total count
            pipeline.push({
                $facet: {
                    data: [
                        { $skip: skip },
                        { $limit: pageSize }
                    ],
                    total: [
                        { $count: "count" }
                    ]
                }
            });

            // Run the aggregation
            const [result] = await Model.aggregate(pipeline);

            // Extract results and total count
            const data = result.data;
            const total = result.total.length > 0 ? result.total[0].count : 0;
            const totalPages = Math.ceil(total / pageSize);

            // Return paginated response
            return {
                success: true,
                data,
                pagination: {
                    page,
                    pageSize,
                    total,
                    totalPages
                }
            };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to search resource" };
        }
    },

    // Get a single resource by ID
    getResource: async (tableName: string, params: any) => {
        try {
            const Model = getModel(tableName);

            // Support both _id and custom id field
            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            const result = await Model.findOne(query).lean();
            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to get resource" };
        }
    },

    // Delete a resource by ID
    deleteResource: async (tableName: string, params: any) => {
        try {
            const Model = getModel(tableName);

            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            const result = await Model.findOneAndDelete(query);
            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to delete resource" };
        }
    },

    // Update a resource by ID
    updateResource: async (tableName: string, params: any, body: any) => {
        try {
            const Model = getModel(tableName);

            // Convert string ObjectIds to MongoDB ObjectIds before updating
            const convertedBody = convertStringsToObjectIdsAndDates(body, Model.schema);

            const query = params.id ?
                (mongoose.Types.ObjectId.isValid(params.id) ?
                    { _id: params.id } :
                    { id: params.id }) :
                params;

            const result = await Model.findOneAndUpdate(
                query,
                { $set: convertedBody },
                { new: true, runValidators: true }
            );

            if (!result) throw new NotFoundError(`Resource not found with id: ${params.id}`);
            return { success: true, data: result };
        } catch (error: any) {
            if (error.name === "ValidationError") {
                return {
                    success: false,
                    error: "Validation failed",
                    details: error.errors || error.message
                };
            }
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return { success: false, error: error.message || "Failed to update resource" };
        }
    },

    // Direct aggregation pipeline execution
    directAggregation: async (tableName: string, pipelineBody: any[]) => {
        try {
            const Model = getModel(tableName);

            // Process each pipeline stage to convert string ObjectIds to real ObjectIds
            const processedPipeline = pipelineBody.map(stage => {
                const processedStage: any = {};
                for (const [key, value] of Object.entries(stage)) {
                    processedStage[key] = convertStringsToObjectIdsAndDates(value, Model.schema);
                }
                return processedStage;
            });

            // Run the aggregation directly with the processed pipeline
            const result = await Model.aggregate(processedPipeline);

            return {
                success: true,
                data: result
            };
        } catch (error: any) {
            if (error instanceof NotFoundError) {
                return { success: false, error: error.message, status: error.status };
            }
            return {
                success: false,
                error: error.message || "Failed to execute direct aggregation",
                stack: error.stack
            };
        }
    }
};

export default searchService;
